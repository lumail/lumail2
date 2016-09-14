--
-- Implementation of the mail threading algorithm described by
-- Jamie Zawinsky with one difference in the 5th step.
-- Description: https://www.jwz.org/doc/threading.html
--
-- Copyright (c) 2016 by Florian Fischer. All rights reserved.
--
---
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; version 2 dated June, 1991, or (at your
-- option) any later version.
--
-- The license text is included in the LICENSE file at the root of the project.
--
-- The algorithm uses lumail2's message objects so it won't work outside of
-- lumail2. But changing the message representation shouldn't be very hard.
--
----
-----
----
--
-- This object can be used as follows:
--
--      Threader = require("threader")
--
--      local threads = Threader.thread messages)
--
--      local sorted_threads = Threader.sort(threads, false)
--

require "table_utilities"

--
-- A Container to group messages in a tree structure
--
local Container = {}
Container.__index = Container

--
-- Create a new container.
--
function Container.new (msg)
  local self = {
    parent = nil,
    message = msg,
    children = {},
  }
  return setmetatable(self, Container)
end

--
-- Check if a unread message is in the subtree.
--
function Container.has_unread (self)
  if self.message and self.message:is_new() then
    return true
  end
  for i, v in ipairs(self.children) do
    if v:has_unread() then
      return true
    end
  end
  return false
end

--
-- Check if cont is reachable.
--
function Container.has_descandent (self, cont)
  if self == cont then
    return true
  end
  if #self.children == 0 then
    return false
  end
  for _, child in ipairs(self.children) do
    if child:has_descandent(cont) then
      return true
    end
  end
  return false
end

--
-- Add a child.
--
function Container.add_child (self, child)
  if child.parent then
    child.parent:remove_child(child)
  end
  child.parent = self
  table.insert(self.children, child)
end

--
-- Remove a child.
--
function Container.remove_child (self, child)
  table.delete(self.children, child)
  child.parent = nil
end

--
-- Transfer all children.
--
function Container.transfer_children (self, new)
  -- reverse iterate the children, because we change the table during
  -- iteration..
  local i = #self.children
  while i > 0 do
    self.children[i].parent = new
    table.insert(new.children, self.children[i])
    self.children[i] = nil
    i = i - 1
  end
end

--
-- Get the subject of a container or its first child.
-- This may break before all empty containers were removed (4.).
-- Because it assumes that all empty containers have a non empty child.
--
function Container.find_subject (self)
  if self.subject then
    return self.subject
  else
    local subject = ""
    if self.message then
      subject = self.message:header "Subject"
    else
      subject = self.children[1].message:header "Subject"
    end
    self.subject = subject
    return subject
  end
end

--
-- Return the container's subject without "Re:" or "Fwd:".
--
function Container.get_normalized_subject (self)
  local subject = self:find_subject()
  -- Strip "Re:" and "Fwd:" from the subject.
  -- Lua's pattern are very limited so this is not possible with one
  -- pattern.
  -- Re:
  subject = string.gsub(subject, "R[Ee]:%s?", "")
  -- Re[%d]:
  subject = string.gsub(subject, "R[Ee]%[%d%]:%s?", "")
  -- Fwd:
  subject = string.gsub(subject, "F[wW][dD]:%s?", "")
  return subject
end

--
-- Check if the container's subject start with something like "Re:".
--
function Container.is_reply (self)
  -- Again lua's pattern make this ugly.
  local subject = self:find_subject()

  return string.match(subject, "R[eE]:%s?") or string.match(subject, "R[eE]%[%d%]:%s?")
end

--
-- Recursively delete all empty containers.
-- See: 4. Prune empty containers
--
function Container.prune_empty (self)
    -- Reverse walk children because we change the table during iteration.
    -- After prune_empty on children[i] only fields >= i could be changed.
    local i = #self.children
    while i > 0 do
        self.children[i]:prune_empty()
        i = i - 1
    end
    if not self.message then
        -- non root
        if self.parent then
            -- empty container without children -> delete it
            if #self.children == 0 then
                self.parent:remove_child(self)
                -- not root container with children
                --  -> delete after transferring the children to parent
            else
                self:transfer_children(self.parent)
                self.parent:remove_child(self)
            end
            -- root container with one child -> replace empty container with child
        elseif #self.children == 1 then
            -- return the child with is now a root.
            -- the calling function has to insert it into the root set.
            local child = self.children[1]
            self:remove_child(child)
            child:transfer_children(self)
            self.message = child.message
        end
    end
end

--
-- Wrapper to use message compare functions on containers.
-- This will fail on empty containers.
--
function Container.cmp_wrapper (cmp_func)
  return function (a, b)
    return cmp_func(a.message, b.message)
  end
end

--
-- Recursively sort the tree with the given compare function.
--
function Container.sort (self, cmp_func)
  for i, v in ipairs(self.children) do
    v:sort(cmp_func)
  end
  -- sort children
  table.sort(self.children, Container.cmp_wrapper(cmp_func))
end

--
-- Get the references of a message.
--
-- References are all message-ids in the "References" header field and the
-- first message-id in the "In-Reply-To" header field if it was not in the
-- Reference field.
--
function Container.get_references (self)
  local references = {}

  for ref in string.gmatch(self.message:header "References", "<([^>]+)>") do
    table.insert(references, ref)
  end

  local reply_to = string.match(self.message:header "In-Reply-To", ".*<([^>]+)>.*")

  if references[#references] ~= reply_to then
    table.insert(references, reply_to)
  end

  return references
end

local Threader = {}
Threader.__index = Threader

-- Table to store messages which got lost because duplicated Message-IDs.
Threader.overridden = {}

--
-- Thread messages.
--
function Threader.thread (messages)
  -- build up the threads
  -- hash table message-id:container
  local id_table = {}
  -- list of root containers/threads
  local roots = {}

  -- 1:
  for _, msg in ipairs(messages) do
    -- 1.A: create/get container of the current message
    local msgid = msg:header "Message-ID"
    msgid = string.match(msgid, "<([^>]+)>")

    -- if the message has no message-id add it to the root set, because
    -- we can not thread it.
    if not msgid then
      table.insert(roots, Container.new(msg))
      -- skip the rest of the loop
      goto missing_msgid
    end

    local par = id_table[msgid]
    if not par then
      par = Container.new(msg)
      id_table[msgid] = par
    else
      -- TODO don't simple override message.
      -- We lose messages with the same id.

      if par.message then
        Threader.overridden[par.message] = 1
      end
      par.message = msg
    end

    -- 1.B: find and link the containers like
    --      they appear in the "References" header.
    local prev = nil
    for _, ref in ipairs(par:get_references()) do
      local cur = id_table[ref]
      if not cur then
        cur = Container.new(nil)
        id_table[ref] = cur
      end
      -- Don't link if they are already linked or we would introduce a
      -- loop.
      if prev and not cur.parent and not cur:has_descandent(prev) then
        prev:add_child(cur)
      end
      prev = cur
    end
    -- 1.C: Link the current message. Ignore if it is already linked.
    if prev and not par:has_descandent(prev) then
      prev:add_child(par)
    end

    -- goto point for messages without message-id
    ::missing_msgid::
  end

  -- 2: find root set
  for _, v in pairs(id_table) do
    if v.parent == nil then
      table.insert(roots, v)
    end
  end

  -- 3: Delete id_table
  --    This is not important we could keep it if we want to use it.
  id_table = nil

  -- 4: Prune empty containers
  for i, v in ipairs(roots) do
    v:prune_empty()
  end

  -- 5: Group root set by subject
  -- 5.A:
  -- hash table normalized_subject:container
  local subject_table = {}
  -- 5.B: find subject of this tree
  local without_subject = {}
  for _, root in ipairs(roots) do

    local subject = root:get_normalized_subject()
    if subject ~= "" then
      local target = subject_table[subject]
      if not target or (target.message and not root.message) then
        subject_table[subject] = root
      end
    else
      table.insert(without_subject, root)
    end
  end
  -- 5.C: Group by subject
  -- Difference to the original algorithm:
  -- Prefer non-replies, older than any child of the empty container, over
  -- the empty container
  for _, root in ipairs(roots) do
    local subject = root:get_normalized_subject()
    local target = subject_table[subject]
    if target and target ~= root then
      -- both are empty -> merge them
      if not target.message and not root.message then
        root:transfer_children(target)
        -- one is empty -> keep empty
      elseif not target.message then
        target:add_child(root)
      elseif not root.message then
        root:add_child(target)
        subject_table[subject] = root
        -- both are not empty
      else
        local is_root_reply = root:is_reply()
        local is_target_reply = target:is_reply()

        -- make reply child of the non reply
        if is_root_reply and not is_target_reply then
          target:add_child(root)
        elseif not is_root_reply and is_target_reply then
          subject_table[subject] = root
          root:add_child(target)
          -- both are either replies or non-replies -> make new parent container
        else
          local parent = Container.new(nil)
          parent:add_child(root)
          parent:add_child(target)
          subject_table[subject] = parent
        end
      end
    end
  end

  -- DIFFERENCE to the original.
  -- Replace empty root containers with their oldest child, if it is
  -- not a reply, to get deterministic results.
  for k, r in pairs(subject_table) do
    if not r.message then
      -- find oldest child
      local oldest = r.children[1]
      local oldest_ctime = oldest.message:to_ctime()
      for _, c in ipairs(r.children) do
        local c_ctime = c.message:to_ctime()
        if c_ctime < oldest_ctime then
          oldest = c
          oldest_ctime = c_ctime
        end
      end
      -- Oldest AND non-reply
      if not oldest:is_reply() then
        r:remove_child(oldest)
        r:transfer_children(oldest)
        subject_table[k] = oldest
      end
    end -- empty
  end -- for-loop

  -- merge subject_table and without_subject into new roots
  roots, without_subject = without_subject, nil
  for k, v in pairs(subject_table) do
    table.insert(roots, v)
  end

  return roots
end

--
-- Sort the threads with the given compare function.
--
-- If promote_unread is true threads with unread message
-- will be placed below threads without unread messages.
--
-- TODO Add option for root sort criteria: first, min, max
--
function Threader.sort (roots, cmp_func, promote_unread)
  for i, v in ipairs(roots) do
    v:sort(cmp_func)
  end

  -- use first child of empty root containers
  local root_cmp_wrapper = function (a, b)
    if not a.message then
      a = a.children[1]
    end
    if not b.message then
      b = b.children[1]
    end
    return Container.cmp_wrapper(cmp_func)(a, b)
  end

  -- sort roots
  table.sort(roots, root_cmp_wrapper)

  -- promote threads with unread messages
  if promote_unread then
    local i = #roots
    while i > 0 do
      if roots[i]:has_unread() then
        table.insert(roots, table.remove(i))
      end
      i = i - 1
    end
  end
  return roots
end

return Threader