---@meta

---@alias MarkdownTableWrapMode "source"|"inline"|"reader"|"float"
---@alias MarkdownTableWrapOpenStrategy "edit"|"split"|"vsplit"|"tab"
---@alias MarkdownTableWrapMappingKey string|false
---@alias MarkdownTableWrapHighlightSpec table<string, any>

---@class MarkdownTableWrapSourceSpan
---@field start_lnum integer
---@field start_col integer 0-based byte column
---@field end_lnum integer
---@field end_col integer 0-based exclusive byte column

---@class MarkdownTableWrapInlineToken
---@field kind "text"|"code"|"bold"|"italic"|"strike"|"mark"|"link"|"wiki_link"|"image"|"break"
---@field text string
---@field source_start_col integer
---@field source_end_col integer
---@field render_start_col integer
---@field render_end_col integer
---@field target? string
---@field target_kind? "inline"|"reference"|"autolink"|"legacy"
---@field reference? string
---@field children? MarkdownTableWrapInlineToken[]
---@field nested_target? boolean

---@class MarkdownTableWrapCell
---@field text string
---@field raw string
---@field spans table[]
---@field tokens MarkdownTableWrapInlineToken[]
---@field table_id string
---@field row_index integer
---@field column_index integer
---@field present boolean
---@field source_span MarkdownTableWrapSourceSpan

---@class MarkdownTableWrapRow
---@field [integer] MarkdownTableWrapCell
---@field kind "header"|"body"
---@field table_id string
---@field row_index integer
---@field source_lnum integer
---@field source_span MarkdownTableWrapSourceSpan
---@field raw_cell_count integer
---@field overflow_cells MarkdownTableWrapCell[]

---@class MarkdownTableWrapTable
---@field id string
---@field start_lnum integer
---@field separator_lnum integer
---@field end_lnum integer
---@field source_span MarkdownTableWrapSourceSpan
---@field header MarkdownTableWrapRow
---@field rows MarkdownTableWrapRow[]
---@field delimiter { source_lnum: integer, source_span: MarkdownTableWrapSourceSpan, cells: MarkdownTableWrapCell[] }
---@field align ("left"|"center"|"right")[]
---@field container? { kind: "blockquote", depth: integer, render_prefix: string }
---@field source_bufnr? integer
---@field changedtick? integer
---@field discovery_backend? "lua"|"treesitter"

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
---@field table? { start_lnum: integer, separator_lnum: integer, end_lnum: integer, columns: integer, excess_cells: integer }
---@field cell? { index: integer, start_col: integer, end_col: integer, text: string, source_span?: MarkdownTableWrapSourceSpan, table_id?: string, row_index?: integer, present?: boolean, tokens?: MarkdownTableWrapInlineToken[], spans?: table[] }
---@field cache { changedtick: integer, rendered: boolean, paused: boolean, auto_preview: boolean, enabled: boolean, entries: integer, stages: string[], hits: integer, misses: integer, token_entries: integer }
---@field discovery { requested: "auto"|"lua"|"treesitter", used: "lua"|"treesitter", fallback_reason?: string, range_count: integer }
---@field config MarkdownTableWrapConfig

---@class MarkdownTableWrapReaderMappings
---@field enabled? boolean
---@field close? MarkdownTableWrapMappingKey
---@field edit? MarkdownTableWrapMappingKey
---@field open_link? MarkdownTableWrapMappingKey
---@field help? MarkdownTableWrapMappingKey
---@field copy_cell? MarkdownTableWrapMappingKey
---@field copy_table? MarkdownTableWrapMappingKey
---@field insert? string[]
---@field passthrough? table<string, string|table>
---@field cell? MarkdownTableWrapCellMappings|false

---@class MarkdownTableWrapCellMappings
---@field enabled? boolean
---@field yank? MarkdownTableWrapMappingKey
---@field visual? MarkdownTableWrapMappingKey
---@field delete? MarkdownTableWrapMappingKey
---@field change? MarkdownTableWrapMappingKey
---@field put? MarkdownTableWrapMappingKey
---@field change_operator? MarkdownTableWrapMappingKey Native Source change-operator proxy; defaults to c
---@field repeat_change? MarkdownTableWrapMappingKey

---@class MarkdownTableWrapFloatMappings
---@field enabled? boolean
---@field close? string|string[]|false
---@field open_link? MarkdownTableWrapMappingKey
---@field help? MarkdownTableWrapMappingKey

---@class MarkdownTableWrapDiscoveryConfig
---@field backend? "auto"|"lua"|"treesitter"

---@class MarkdownTableWrapCacheConfig
---@field enabled? boolean

---@class MarkdownTableWrapReaderConfig
---@field auto_open? "has_table"|"always"
---@field wrap? boolean
---@field linebreak? boolean
---@field breakindent? boolean
---@field conceallevel? integer
---@field concealcursor? string
---@field sticky_header? boolean

---@class MarkdownTableWrapWideColumn
---@field width? integer
---@field min? integer
---@field max? integer
---@field weight? number
---@field priority? integer

---@class MarkdownTableWrapWideViewport
---@field start_column? integer
---@field column_count? integer
---@field marker? string

---@class MarkdownTableWrapWideTableConfig
---@field mode? "wrap"|"viewport"
---@field allocate_extra? boolean
---@field viewport? MarkdownTableWrapWideViewport
---@field columns? table<integer, MarkdownTableWrapWideColumn>

---@class MarkdownTableWrapWikiLinkConfig
---@field icon? string
---@field highlight? string
---@field scope_highlight? string

---@class MarkdownTableWrapCustomLinkConfig
---@field pattern? string
---@field icon? string
---@field highlight? string

---@class MarkdownTableWrapLinkConfig
---@field icon? string
---@field wiki? MarkdownTableWrapWikiLinkConfig
---@field image? string
---@field allowed_schemes? string[]
---@field custom? table<string, MarkdownTableWrapCustomLinkConfig>
---@field resolver? fun(target: MarkdownTableWrapTarget, context: MarkdownTableWrapContext, strategy: MarkdownTableWrapOpenStrategy): boolean|string|nil

---@class MarkdownTableWrapMappingsConfig
---@field reader? MarkdownTableWrapReaderMappings|false
---@field float? MarkdownTableWrapFloatMappings|false

---@class MarkdownTableWrapConfig
---@field max_width_ratio? number
---@field min_col_width? integer
---@field max_col_width? integer
---@field fit_to_window? boolean
---@field border? string
---@field use_unicode_border? boolean
---@field table_border? "rounded"|"single"
---@field row_separator? boolean
---@field preview_mode? "reader"|"inline"|"float"
---@field inline_mode? "replace"|"insert"
---@field inline_position? "above"|"below"
---@field dim_source? boolean
---@field auto_preview? boolean
---@field render_all? boolean
---@field auto_preview_in_insert? boolean
---@field clear_on_cursor_leave? boolean
---@field clear_on_insert? boolean
---@field clear_on_visual? boolean
---@field debounce_ms? integer
---@field discovery? MarkdownTableWrapDiscoveryConfig
---@field cache? MarkdownTableWrapCacheConfig
---@field overlay_priority? integer
---@field overlay_fill? boolean
---@field inline_virtual_text? "overlay"|"win_col"
---@field inline_disable_wrap? boolean
---@field inline_wrap_scope? "always"|"cursor"|"never"
---@field inline_viewport_scrolling? boolean
---@field wide_table? MarkdownTableWrapWideTableConfig
---@field reader? MarkdownTableWrapReaderConfig
---@field highlight_preset? string
---@field theme_dir? string
---@field themes? table<string, table<string, MarkdownTableWrapHighlightSpec>>
---@field extra_filetypes? string[]
---@field highlights? table<string, MarkdownTableWrapHighlightSpec>
---@field map_gx? boolean
---@field mappings? MarkdownTableWrapMappingsConfig
---@field link? MarkdownTableWrapLinkConfig

---@class MarkdownTableWrapSetupOptions : MarkdownTableWrapConfig
---@field reset_state? boolean Clear per-buffer pause, mode, auto-preview, and viewport intent during setup

return {}
