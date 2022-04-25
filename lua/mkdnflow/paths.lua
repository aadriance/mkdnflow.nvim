-- mkdnflow.nvim (Tools for fluent markdown notebook navigation and management)
-- Copyright (C) 2022 Jake W. Vincent <https://github.com/jakewvincent>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
-- This module: File and link navigation functions

-- Get OS for use in a couple of functions
local this_os = require('mkdnflow').this_os
-- Generic OS message
local this_os_err = '⬇️ Function unavailable for '..this_os..'. Please file an issue.'
-- Get config setting for whether to make missing directories or not
local create_dirs = require('mkdnflow').config.create_dirs
-- Get config setting for where links should be relative to
local links_relative_to = require('mkdnflow').config.links_relative_to.target
-- Get directory of first-opened file
local initial_dir = require('mkdnflow').initial_dir
-- Get root_dir for notebook/wiki
local root_dir = require('mkdnflow').root_dir

-- Load modules
local buffers = require('mkdnflow.buffers')
local bib = require('mkdnflow.bib')
local cursor = require('mkdnflow.cursor')
local links = require('mkdnflow.links')

--[[
path_type() determines what kind of path is in a url
Returns a string:
     1. 'file' if the path has the 'file:' prefix,
     2. 'url' is the result of hasUrl(path) is true
     3. 'filename' if (1) and (2) aren't true
--]]
local path_type = function(path)
    if string.find(path, '^file:') then
        return('file')
    elseif links.hasUrl(path) then
        return('url')
    elseif string.find(path, '^@') then
        return('citation')
    elseif string.find(path, '^#') then
        return('anchor')
    else
        return('filename')
    end
end


--[[
does_exist() determines whether the path specified as the argument exists
NOTE: Assumes that the initially opened file is in an existing directory!
--]]
local does_exist = function(path, type)
    -- If type is not specified, use "d" (directory) by default
    type = type or "d"
    if this_os == "Linux" or this_os == "POSIX" or this_os == "Darwin" then
        -- Use the shell to determine if the path exists
        local handle = io.popen(
            'if [ -'..type..' "'..path..'" ]; then echo true; else echo false; fi'
        )
        local exists = handle:read('*l')
        io.close(handle)
        -- Get the contents of the first (only) line & store as a boolean
        if exists == 'false' then
            exists = false
        else
            exists = true
        end
        -- Return the existence property of the path
        return(exists)
    elseif this_os == 'Windows_NT' then
        -- Add a backslash if we're searching for a directory
        if type == 'd' then type = '\\' else type = '' end
        -- Use the shell to determine if the path exists
        local handle = io.popen('IF exist '..path..type..' ( echo true ) ELSE ( echo false )')
        local exists = handle:read('*l')
        io.close(handle)
        if exists:match('true') then
            exists = true
        else
            exists = false
        end
        -- Return the existence property of the path
        return(exists)
    else
        print(this_os_err)
        -- Return nothing in the else case
        return(nil)
    end
end

--[[
escape_chars() escapes the set of characters in 'chars' with the mappings in
'replacements'. For shell escapes.
--]]
local escape_chars = function(string)
    -- Which characters to match
    local chars = "[ '&()$]"
    -- Set up table of replacements
    local replacements = {
        [" "] = "\\ ",
        ["'"] = "\\'",
        ["&"] = "\\&",
        ["("] = "\\(",
        [")"] = "\\)",
        ["$"] = "\\$",
        ["#"] = "\\#",
    }
    -- Do the replacement
    local escaped = string.gsub(string, chars, replacements)
    -- Return the new string
    return(escaped)
end

local escape_chars_windows = function(string)
    -- Which characters to match
    --local chars = "[ '&()$]"
    local chars = "[ &]"
    -- Set up table of replacements
    local replacements = {
        [" "] = "^ ",
        --["'"] = "\\'",
        ["&"] = "^&",
        --["("] = "\\(",
        --[")"] = "\\)",
        --["$"] = "\\$",
        --["#"] = "\\#",
    }
    -- Do the replacement
    local escaped = string.gsub(string, chars, replacements)
    -- Return the new string
    return(escaped)
end

--[[
escape_lua_chars() escapes the set of characters in 'chars' with the mappings
provided in 'replacements'. For Lua escapes.
--]]
local escape_lua_chars = function(string)
    -- Which characters to match
    local chars = "[-.'\"a]"
    -- Set up table of replacements
    local replacements = {
        ["-"] = "%-",
        ["."] = "%.",
        ["'"] = "\'",
        ['"'] = '\"'
    }
    -- Do the replacement
    local escaped = string.gsub(string, chars, replacements)
    -- Return the new string
    return(escaped)
end

local handle_internal_file = function(path)
    if this_os == 'Windows_NT' then
        -- Get the name of the file in the link path. Will return nil if the
        -- link doesn't contain any directories.
        local filename = string.match(path, '.*\\(.-)$')
        -- Get the name of the directory path to the file in the link path. Will
        -- return nil if the link doesn't contain any directories.
        local dir = string.match(path, '(.*)\\.-$')
        -- If so, go to the path specified in the output
        -- Check if the user wants directories to be created and if
        -- a directory is specified in the link that we need to check
        if create_dirs and dir then
            -- If so, check how the user wants links to be interpreted
            if links_relative_to == 'root' then
                -- Paste root directory and the directory in link
                local paste = root_dir..'\\'..dir
                -- See if the path exists
                local exists = does_exist(paste)
                print(exists)
                -- If the path doesn't exist, make it
                if not exists then
                    print('Now trying to make '..paste)
                    os.execute('mkdir "'..paste..'"')
                end
                -- Remember the buffer we're currently in and follow path
                buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
                vim.cmd(':e '..paste..'\\'..filename)
            elseif links_relative_to == 'first' then
                -- Paste together the directory of the first-opened file
                -- and the directory in the link path
                local paste = initial_dir..'\\'..dir
                -- See if the path exists
                local exists = does_exist(paste)
                -- If the path doesn't exist, make it!
                if not exists then
                    -- Send command to shell
                    os.execute('mkdir "'..paste..'"')
                end
                -- Remember the buffer we're currently viewing
                buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
                -- And follow the path!
                vim.cmd(':e '..paste..'\\'..filename)
            else -- Otherwise, they want it relative to the current file
                -- So, get the path of the current file
                local cur_file = vim.api.nvim_buf_get_name(0)
                -- Get the directory the current file is in
                local cur_file_dir = string.match(cur_file, '(.*)\\.-$')
                -- Paste together the directory of the current file and the
                -- directory path provided in the link
                local paste = cur_file_dir..'\\'..dir
                -- See if the path exists
                local exists = does_exist(paste)
                -- If the path doesn't exist, make it!
                if not exists then
                    -- Send command to shell
                    os.execute('mkdir "'..paste..'"')
                end
                -- Remember the buffer we're currently viewing
                buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
                -- And follow the path!
                vim.cmd(':e '..paste..'\\'..filename)
            end
        -- Otherwise, if links are interpreted rel to first-opened file
        elseif links_relative_to == 'root' then
            -- Get the path of the current file
            local cur_file = vim.api.nvim_buf_get_name(0)
            -- Paste together root directory path & path in link
            local paste = root_dir..'\\'..path
            -- Remember the buffer we're currently viewing
            buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
            -- And follow the path!
            vim.cmd(':e '..paste)
        elseif links_relative_to == 'current' then
            -- Get the path of the current file
            local cur_file = vim.api.nvim_buf_get_name(0)
            -- Get the directory the current file is in
            local cur_file_dir = string.match(cur_file, '(.*)\\.-$')
            -- Paste together the directory of the current file and the
            -- directory path provided in the link
            local paste = cur_file_dir..'\\'..path
            -- Remember the buffer we're currently viewing
            buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
            -- And follow the path!
            vim.cmd(':e '..paste)
        else -- Otherwise, links are relative to the first-opened file
            -- Paste the dir of the first-opened file and path in the link
            local paste = initial_dir..'\\'..path
            -- Remember the buffer we're currently viewing
            buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
            -- And follow the path!
            vim.cmd(':e '..paste)
        end
    else
        -- Get the name of the file in the link path. Will return nil if the
        -- link doesn't contain any directories.
        local filename = string.match(path, '.*/(.-)$')
        -- Get the name of the directory path to the file in the link path. Will
        -- return nil if the link doesn't contain any directories.
        local dir = string.match(path, '(.*)/.-$')
        -- If so, go to the path specified in the output
        -- Check if the user wants directories to be created and if
        -- a directory is specified in the link that we need to check
        if create_dirs and dir then
            -- If so, check how the user wants links to be interpreted
            if links_relative_to == 'root' then
                -- Paste root directory and the directory in link
                local paste = root_dir..'/'..dir
                -- See if the path exists
                local exists = does_exist(paste)
                -- If the path doesn't exist, make it
                if not exists then
                    local se_paste = escape_chars(paste)
                    os.execute('mkdir -p '..se_paste)
                end
                -- Remember the buffer we're currently in and follow path
                buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
                vim.cmd(':e '..paste..'/'..filename)
            elseif links_relative_to == 'first' then
                -- Paste together the directory of the first-opened file
                -- and the directory in the link path
                local paste = initial_dir..'/'..dir
                -- See if the path exists
                local exists = does_exist(paste)
                -- If the path doesn't exist, make it!
                if not exists then
                    -- Escape special characters in path
                    local sh_esc_paste = escape_chars(paste)
                    -- Send command to shell
                    os.execute('mkdir -p '..sh_esc_paste)
                end
                -- Remember the buffer we're currently viewing
                buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
                -- And follow the path!
                vim.cmd(':e '..paste..'/'..filename)
            else -- Otherwise, they want it relative to the current file
                -- So, get the path of the current file
                local cur_file = vim.api.nvim_buf_get_name(0)
                -- Get the directory the current file is in
                local cur_file_dir = string.match(cur_file, '(.*)/.-$')
                -- Paste together the directory of the current file and the
                -- directory path provided in the link
                local paste = cur_file_dir..'/'..dir
                -- See if the path exists
                local exists = does_exist(paste)
                -- If the path doesn't exist, make it!
                if not exists then
                    -- Escape special characters in path
                    local se_paste = escape_chars(paste)
                    -- Send command to shell
                    os.execute('mkdir -p '..se_paste)
                end
                -- Remember the buffer we're currently viewing
                buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
                -- And follow the path!
                vim.cmd(':e '..paste..'/'..filename)
            end
        -- Otherwise, if links are interpreted rel to first-opened file
        elseif links_relative_to == 'root' then
            -- Get the path of the current file
            local cur_file = vim.api.nvim_buf_get_name(0)
            -- Paste together root directory path & path in link
            local paste = root_dir..'/'..path
            -- Remember the buffer we're currently viewing
            buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
            -- And follow the path!
            vim.cmd(':e '..paste)
        elseif links_relative_to == 'current' then
            -- Get the path of the current file
            local cur_file = vim.api.nvim_buf_get_name(0)
            -- Get the directory the current file is in
            local cur_file_dir = string.match(cur_file, '(.*)/.-$')
            -- Paste together the directory of the current file and the
            -- directory path provided in the link
            local paste = cur_file_dir..'/'..path
            -- Remember the buffer we're currently viewing
            buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
            -- And follow the path!
            vim.cmd(':e '..paste)
        else -- Otherwise, links are relative to the first-opened file
            -- Paste the dir of the first-opened file and path in the link
            local paste = initial_dir..'/'..path
            -- Remember the buffer we're currently viewing
            buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
            -- And follow the path!
            vim.cmd(':e '..paste)
        end
    end
end

--[[
open() handles vim-external paths, including local files or web URLs
Returns nothing
--]]
local open = function(path)
    local shell_open = function(path_)
        if this_os == "Linux" then
            vim.api.nvim_command('silent !xdg-open '..path_)
        elseif this_os == "Darwin" then
            vim.api.nvim_command('silent !open '..path_..' &')
        elseif this_os == 'Windows_NT' then
            vim.api.nvim_command('silent !cmd.exe /c "start "" "'..path_..'"')
        else
            print(this_os_err)
        end
    end
    -- If the file exists, handle it; otherwise, print a warning
    -- Don't want to use the shell-escaped version; it will throw a
    -- false alert if there are escape chars
    if links.hasUrl(path) then
        shell_open(path)
    elseif does_exist(path, "f") == false and
        does_exist(path, "d") == false then
        print("⬇️  "..path.." doesn't seem to exist!")
    else
        shell_open(path)
    end
end

local handle_external_file_unix = function(path)
    -- Get what's after the file: tag
    local real_path = string.match(path, '^file:(.*)')
    -- Check if path provided is absolute or relative to $HOME
    if string.match(real_path, '^~/') or string.match(real_path, '^/') then
        local se_paste = escape_chars(real_path)
        -- If the path starts with a tilde, replace it w/ $HOME
        if string.match(real_path, '^~/') then
            se_paste = string.gsub(se_paste, '^~/', '$HOME/')
        end
        -- Pass to the open() function
        open(se_paste)
    elseif links_relative_to == 'root' then
        -- Paste together root directory path and path in link
        local paste = root_dir..'/'..real_path
        -- Escape special characters
        local se_paste = escape_chars(paste)
        -- Pass to the open() function
        open(se_paste)
    elseif links_relative_to == 'current' then
        -- Get the path of the current file
        local cur_file = vim.api.nvim_buf_get_name(0)
        -- Get the directory the current file is in
        local cur_file_dir = string.match(cur_file, '(.*)/.-$')
        -- Paste together the directory of the current file and the
        -- directory path provided in the link, and escape for shell
        local se_paste = escape_chars(cur_file_dir..'/'..real_path)
        -- Pass to the open() function
        open(se_paste)
    else
        -- Otherwise, links are relative to the first-opened file, so
        -- paste together the directory of the first-opened file and the
        -- path in the link and escape for the shell
        local se_paste = escape_chars(initial_dir..'/'..real_path)
        -- Pass to the open() function
        open(se_paste)
    end
end

local handle_external_file_windows = function(path)
    -- Get what's after the file: tag
    local real_path = string.match(path, '^file:(.*)')
    -- Check if path provided is absolute
    if string.match(real_path, '^%u:\\') then
        open(real_path)
    elseif links_relative_to == 'root' then
        -- Paste together root directory path and path in link
        local paste = root_dir..'\\'..real_path
        -- Pass to the open() function
        open(paste)
    elseif links_relative_to == 'current' then
        -- Get the path of the current file
        local cur_file = vim.api.nvim_buf_get_name(0)
        -- Get the directory the current file is in
        local cur_file_dir = string.match(cur_file, '(.*)\\.-$')
        -- Paste together the directory of the current file and the
        -- directory path provided in the link, and escape for shell
        local paste = cur_file_dir..'\\'..real_path
        -- Pass to the open() function
        open(paste)
    else
        -- Otherwise, links are relative to the first-opened file, so
        -- paste together the directory of the first-opened file and the
        -- path in the link and escape for the shell
        local paste = initial_dir..'\\'..real_path
        -- Pass to the open() function
        open(paste)
    end
end

local M = {}

--[[
handlePath() does something with the path in the link under the cursor:
     1. Creates the file specified in the path, if the path is determined to
        be a filename,
     2. Uses open() to open the URL specified in the path, if the path
        is determined to be a URL, or
     3. Uses open() to open a local file at the specified path via the
        system's default application for that filetype, if the path is dete-
        rmined to be neither the filename for a text file nor a URL.
Returns nothing
--]]
M.handlePath = function(path)
    if path_type(path) == 'filename' then
        handle_internal_file(path)
    elseif path_type(path) == 'url' then
        local se_path = vim.fn.shellescape(path)
        open(se_path)
    elseif path_type(path) == 'file' then
        if this_os == 'Linux' or this_os == 'Darwin' then
            handle_external_file_unix(path)
        elseif this_os == 'Windows_NT' then
            handle_external_file_windows(path)
        else
            print(this_os_err)
        end
    elseif path_type(path) == 'anchor' then
        cursor.toHeading(path)
    elseif path_type(path) == 'citation' then
        -- Retrieve highest-priority field in bib entry (if it exists)
        local field = bib.citationHandler(escape_lua_chars(path))
        -- Use this function to do sth with the information returned (if any)
        if field then M.handlePath(field) end
    end
end

-- Return all the functions added to the table M!
return M
