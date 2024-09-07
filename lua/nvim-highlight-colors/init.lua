local utils = require("nvim-highlight-colors.utils")
local table_utils = require("nvim-highlight-colors.table_utils")
local buffer_utils = require("nvim-highlight-colors.buffer_utils")
local colors = require("nvim-highlight-colors.color.utils")
local color_patterns = require("nvim-highlight-colors.color.patterns")
local ns_id = vim.api.nvim_create_namespace("nvim-highlight-colors")
local defer = require("nvim-highlight-colors.defer")

if vim.g.loaded_nvim_highlight_colors ~= nil then
	return {}
end
vim.g.loaded_nvim_highlight_colors = 1

local render_options = utils.render_options
local row_offset = 2
local is_loaded = false
local options = {
	render = render_options.background,
	enable_hex = true,
	enable_rgb = true,
	enable_hsl = true,
	enable_var_usage = true,
	enable_named_colors = true,
	enable_short_hex = true,
	enable_tailwind = false,
	custom_colors = nil,
	virtual_symbol = "■",
	virtual_symbol_prefix = "",
	virtual_symbol_suffix = " ",
	virtual_symbol_position = "inline",
	exclude_filetypes = {},
	exclude_buftypes = {}
}

local M = {}

---Plugin entry point
---@param user_options table Check 'options' variable above
function M.setup(user_options)
	is_loaded = true
	if (user_options ~= nil and user_options ~= {}) then
		for key, _ in pairs(user_options) do
			if user_options[key] ~= nil then
				options[key] = user_options[key]
			end
		end
	end
end

---Highlight visible colors within specified buffer id
---@param min_row number 
---@param max_row number 
---@param active_buffer_id number 
function M.highlight_colors(min_row, max_row, active_buffer_id)
	local patterns = {}

	local patterns_config = {
		HEX = {
			is_enabled = options.enable_hex,
			patterns = {
				color_patterns.hex_regex,
				color_patterns.hex_0x_regex
			},
		},
		RGB = {
			is_enabled = options.enable_rgb,
			patterns = { color_patterns.rgb_regex },
		},
		HSL = {
			is_enabled = options.enable_hsl,
			patterns = { color_patterns.hsl_regex },
		},
		VAR_USAGE = {
			is_enabled = options.enable_var_usage,
			patterns = { color_patterns.var_usage_regex }
		},
		NAMED_COLORS = {
			is_enabled = options.enable_named_colors,
			patterns = { colors.get_css_named_color_pattern() }
		},
		TAILWIND = {
			is_enabled = options.enable_tailwind and not utils.has_tailwind_css_lsp(),
			patterns = { colors.get_tailwind_named_color_pattern() }
		}
	}

	for _, config in pairs(patterns_config) do
		if config.is_enabled then
			for _, pattern in pairs(config.patterns) do
				table.insert(patterns, pattern)
			end
		end
	end

	if (options.custom_colors ~= nil) then
		for _, custom_color in pairs(options.custom_colors) do
			table.insert(patterns, custom_color.label)
		end
	end

	local positions = buffer_utils.get_positions_by_regex(
		patterns,
		min_row - 1,
		max_row,
		active_buffer_id,
		row_offset
	)

	for _, data in pairs(positions) do
		utils.create_highlight(
			active_buffer_id,
			ns_id,
			data,
			options
		)
	end

	utils.highlight_with_lsp(active_buffer_id, ns_id, positions, options)
end


---Refreshes current highlights within the specified buffer
---@param active_buffer_id number
---@param should_clear_highlights boolean Indicates whether the current highlights should be deleted before rendering
function M.refresh_highlights(active_buffer_id, should_clear_highlights)
	local buffer_id = active_buffer_id ~= nil and active_buffer_id or 0

 	if not vim.api.nvim_buf_is_valid(active_buffer_id)
 		or vim.bo[buffer_id].buftype == "terminal"
 		or vim.tbl_contains(options.exclude_filetypes, vim.bo[buffer_id].filetype)
 		or vim.tbl_contains(options.exclude_buftypes, vim.bo[buffer_id].buftype)
  	then
 		return
 	end

	if should_clear_highlights then
		M.clear_highlights(buffer_id)
	end
	local visible_rows = utils.get_visible_rows_by_buffer_id(buffer_id)
	local min_row = visible_rows[1]
	local max_row = visible_rows[2]
	M.highlight_colors(min_row, max_row, buffer_id)
end

M.debounced_refresh_highlights = defer.debounce_trailing(M.refresh_highlights, 50)

---Deletes highlights for the specified buffer
---@param active_buffer_id number
function M.clear_highlights(active_buffer_id)
	pcall(
		function ()
			local buffer_id = active_buffer_id ~= nil and active_buffer_id or 0

			vim.api.nvim_buf_clear_namespace(buffer_id, ns_id, 0, utils.get_last_row_index())
			local virtual_texts = vim.api.nvim_buf_get_extmarks(buffer_id, ns_id, 0, -1, {})

			if #virtual_texts then
				for _, virtual_text in pairs(virtual_texts) do
					local extmart_id = virtual_text[1]
					if (tonumber(extmart_id) ~= nil) then
						vim.api.nvim_buf_del_extmark(buffer_id, ns_id, extmart_id)
					end
				end
			end
		end
	)
end


---Formats nvim-cmp to showcase colors in the autocomplete
---@usage 
---Add the following to your nvim-cmp setup
---cmp.setup({
---...other configs
---formatting = {
---    format = require("nvim-highlight-colors").format
---}
function M.format(entry, item)
	item.menu = item.kind
	item.kind = item.abbr
	item.kind_hl_group = ''
	item.abbr = ''

	if item.menu ~= "Color" then
		return item
	end

	local entryItem = entry:get_completion_item()
	if entryItem == nil then
		return item
	end

	local entryDoc = entryItem.documentation
	if entryDoc == nil or type(entryDoc) ~= "string" then
		return item
	end

	local color_hex = colors.get_color_value(entryDoc)
	if color_hex == nil then
		return item
	end

	local highlight_group = utils.create_highlight_name("fg-" .. color_hex)
	vim.api.nvim_set_hl(0, highlight_group, { fg = color_hex, default = true })

	item.abbr_hl_group = highlight_group
	item.abbr = options.virtual_symbol

	return item
end

---Callback to manually show the highlights
function M.turn_on()
	local buffers = vim.fn.getbufinfo({ buflisted = true })

	for _, buffer in ipairs(buffers) do
		M.debounced_refresh_highlights(buffer.bufnr, false)
	end

	is_loaded = true
end

---Callback to manually hide the highlights
function M.turn_off()
	local buffers = vim.fn.getbufinfo({ buflisted = true })

	for _, buffer in ipairs(buffers) do
		M.clear_highlights(buffer.bufnr)
	end

	is_loaded = false
end

---Callback to manually toggle the highlights
function M.toggle()
	if is_loaded then
		M.turn_off()
	else
		M.turn_on()
	end
end

---Autocmd callback to handle changes that require a complete redraw of the highlights (clear current highlights + highlight again)
---@param props {buf: number}
function M.handle_change_autocmd_callback(props)
	if is_loaded then
		M.refresh_highlights(props.buf, true)
	end
end

---Autocmd callback to handle changes that do not require a full redraw of the highlights
---@param props {buf: number}
function M.handle_autocmd_callback(props)
	if is_loaded then
		M.debounced_refresh_highlights(props.buf, false)
	end
end

vim.api.nvim_create_autocmd({
	"TextChanged",
	"InsertLeave",
	"TextChangedP",
	"LspAttach",
	"BufEnter",
}, {
	callback = M.handle_change_autocmd_callback,
})

vim.api.nvim_create_autocmd({
	"VimResized",
	"WinScrolled",
}, {
	callback = M.handle_autocmd_callback,
})

vim.api.nvim_create_user_command("HighlightColors",
	function(opts)
		local arg = string.lower(opts.fargs[1])
		if arg == "on" then
			M.turn_on()
		elseif arg == "off" then
			M.turn_off()
		elseif arg == "toggle" then
			M.toggle()
		end
	end,
	{
		nargs = 1,
		complete = function()
			return { "On", "Off", "Toggle" }
		end,
		desc = "Config color highlight"
	}
)

return {
	turnOff = M.turn_off,
	turnOn = M.turn_on,
	setup = M.setup,
	toggle = M.toggle,
	format = M.format,
}
