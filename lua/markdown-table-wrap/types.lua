---@meta

---@alias MarkdownTableWrapMode "source"|"inline"|"reader"|"float"
---@alias MarkdownTableWrapOpenStrategy "edit"|"split"|"vsplit"|"tab"
---@alias MarkdownTableWrapMappingKey string|false

---@class MarkdownTableWrapTarget
---@field kind "external"|"file"|"anchor"|"file_anchor"|"wiki"|"image"|"unresolved"
---@field raw string
---@field path? string
---@field anchor? string
---@field line? integer
---@field label? string
---@field exists? boolean
---@field reason? string

---@class MarkdownTableWrapCursorContext
---@field source_lnum integer
---@field source_col integer
---@field view_lnum? integer
---@field view_col? integer

---@class MarkdownTableWrapContext
---@field mode MarkdownTableWrapMode
---@field source_bufnr integer
---@field source_path? string
---@field view_bufnr integer
---@field winid? integer
---@field cursor MarkdownTableWrapCursorContext
---@field window { width?: integer, height?: integer }
---@field table? { start_lnum: integer, separator_lnum: integer, end_lnum: integer, columns: integer }
---@field cell? { index: integer, start_col: integer, end_col: integer, text: string }
---@field cache { changedtick: integer, rendered: boolean, paused: boolean, auto_preview: boolean }
---@field config MarkdownTableWrapConfig

---@class MarkdownTableWrapReaderMappings
---@field enabled? boolean
---@field close? MarkdownTableWrapMappingKey
---@field edit? MarkdownTableWrapMappingKey
---@field open_link? MarkdownTableWrapMappingKey
---@field help? MarkdownTableWrapMappingKey
---@field insert? string[]
---@field passthrough? table<string, string|table>

---@class MarkdownTableWrapFloatMappings
---@field enabled? boolean
---@field close? string|string[]|false
---@field open_link? MarkdownTableWrapMappingKey
---@field help? MarkdownTableWrapMappingKey

---@class MarkdownTableWrapConfig
---@field max_width_ratio? number
---@field min_col_width? integer
---@field max_col_width? integer
---@field fit_to_window? boolean
---@field preview_mode? "reader"|"inline"|"float"
---@field inline_mode? "replace"|"insert"
---@field auto_preview? boolean
---@field render_all? boolean
---@field reader? table
---@field mappings? { reader?: MarkdownTableWrapReaderMappings|false, float?: MarkdownTableWrapFloatMappings|false }
---@field link? { resolver?: fun(target: MarkdownTableWrapTarget, context: MarkdownTableWrapContext, strategy: MarkdownTableWrapOpenStrategy): boolean|string|nil }

return {}
