-- Bootstrap lazy.nvim using the nixCats wrapper
-- This assumes you copied the luaUtils template into ./lua/nixCatsUtils
-- Correct require path and function name
local lazyCat = require("nixCatsUtils.lazyCat") -- Use lazyCat wrapper

-- Basic Neovim options (similar to kickstart)
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.opt.autowrite = true -- Enable auto write
vim.opt.clipboard = "unnamedplus" -- Sync with system clipboard
vim.opt.completeopt = "menu,menuone,noselect"
vim.opt.conceallevel = 3 -- Hide * markup for bold and italic
vim.opt.confirm = true -- Confirm to save changes before exiting modified buffer
vim.opt.cursorline = true -- Enable highlighting of the current line
vim.opt.expandtab = true -- Use spaces instead of tabs
vim.opt.formatoptions = "jcroqlnt" -- tcqj
vim.opt.grepformat = "%f:%l:%c:%m"
vim.opt.grepprg = "rg --vimgrep"
vim.opt.ignorecase = true -- Ignore case
vim.opt.inccommand = "nosplit" -- preview incremental substitute
vim.opt.laststatus = 0
vim.opt.list = true -- Show some invisible characters (tabs...
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
vim.opt.mouse = "a" -- Enable mouse mode
vim.opt.number = true -- Print line number
vim.opt.pumblend = 10 -- Popup blend
vim.opt.pumheight = 10 -- Maximum number of entries in a popup
vim.opt.relativenumber = true -- Show relative line numbers
vim.opt.scrolloff = 4 -- Lines of context
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }
vim.opt.shiftround = true -- Round indent
vim.opt.shiftwidth = 2 -- Size of an indent
vim.opt.shortmess = vim.opt.shortmess + { c = true }
vim.opt.showmode = false -- Dont show mode since we have a statusline
vim.opt.sidescrolloff = 8 -- Columns of context
vim.opt.signcolumn = "yes" -- Always show the signcolumn, otherwise it would shift the text each time
vim.opt.smartcase = true -- Don't ignore case with capitals
vim.opt.smartindent = true -- Insert indents automatically
vim.opt.spelllang = { "en" }
vim.opt.splitbelow = true -- Put new windows below current
vim.opt.splitkeep = "screen"
vim.opt.splitright = true -- Put new windows right of current
vim.opt.tabstop = 2 -- Number of spaces tabs count for
vim.opt.termguicolors = true -- True color support
vim.opt.timeoutlen = 300 -- Lower timeout length
vim.opt.undofile = true
vim.opt.undolevels = 10000
vim.opt.updatetime = 200 -- Save swap file and trigger CursorHold
vim.opt.wildmode = "longest:full,full" -- Command-line completion mode
vim.opt.winblend = 10
vim.opt.wrap = false -- Disable line wrap

-- Setup lazy.nvim using the nixCats wrapper
-- It automatically detects plugins installed via Nix/nixCats
-- Correct function call: lazyCat.setup
lazyCat.setup(nixCats.pawsible({"allPlugins", "start", "lazy.nvim" }), {
  -- Add or override lazy.nvim plugin specs here if needed
  -- Plugins listed in nixCats config are automatically added by the wrapper if detected

  -- Example: Force load Tokyonight (already in nixCats startupPlugins)
  { "folke/tokyonight.nvim", lazy = false, priority = 1000, opts = {} },

  -- Example: Configure WhichKey (assuming it's in nixCats config)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
    config = function(_, opts)
      vim.o.timeout = true
      vim.o.timeoutlen = 300
      require("which-key").setup(opts)
    end,
  },

  -- Example: Configure Telescope (assuming it's in nixCats config)
  {
    "nvim-telescope/telescope.nvim",
    event = "VeryLazy",
    dependencies = {
      "nvim-lua/plenary.nvim", -- Should be added by nixCats if telescope is included
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        -- Use lazyAdd to make build conditional
        build = require('nixCatsUtils').lazyAdd("make"),
        cond = require('nixCatsUtils').lazyAdd(function()
          return vim.fn.executable("make") == 1
        end),
      },
    },
    config = function()
      require("telescope").setup({
        defaults = {
          mappings = {
            i = { ["<c-enter>"] = "to_fuzzy_refine" },
          },
        },
      })
      -- Add keymaps here
      vim.keymap.set("n", "<leader>?", require("telescope.builtin").oldfiles, { desc = "[?] Find recently opened files" })
      vim.keymap.set("n", "<leader><space>", require("telescope.builtin").buffers, { desc = "[ ] Find existing buffers" })
      vim.keymap.set("n", "<leader>/", function()
        require("telescope.builtin").current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
          winblend = 10,
          previewer = false,
        }))
      end, { desc = "[/] Fuzzily search in current buffer" })
      vim.keymap.set("n", "<leader>sf", require("telescope.builtin").find_files, { desc = "[S]earch [F]iles" })
      vim.keymap.set("n", "<leader>sh", require("telescope.builtin").help_tags, { desc = "[S]earch [H]elp" })
      vim.keymap.set("n", "<leader>sw", require("telescope.builtin").grep_string, { desc = "[S]earch current [W]ord" })
      vim.keymap.set("n", "<leader>sg", require("telescope.builtin").live_grep, { desc = "[S]earch by [G]rep" })
      vim.keymap.set("n", "<leader>sd", require("telescope.builtin").diagnostics, { desc = "[S]earch [D]iagnostics" })
    end,
  },

  -- Example: Configure Treesitter (assuming it's in nixCats config)
  {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" },
    -- Use lazyAdd to make build conditional
    build = require('nixCatsUtils').lazyAdd(":TSUpdate"),
    config = function()
      require("nvim-treesitter.configs").setup({
        highlight = { enable = true },
        indent = { enable = true },
        ensure_installed = {}, -- Grammars managed by Nix
        -- Use lazyAdd to make auto_install conditional
        auto_install = require('nixCatsUtils').lazyAdd(true, false),
      })
    end,
  },

  -- Example: Configure LSP (assuming relevant plugins are in nixCats config)
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
       -- Only enable Mason plugins if NOT using nixCats
      { "williamboman/mason.nvim", enabled = not require('nixCatsUtils').isNixCats },
      { "williamboman/mason-lspconfig.nvim", enabled = not require('nixCatsUtils').isNixCats },
    },
    config = function()
      local lspconfig = require("lspconfig")
      local capabilities = vim.lsp.protocol.make_client_capabilities() -- Base capabilities

      -- Make Mason setup conditional
      if not require('nixCatsUtils').isNixCats then
        local mason = require("mason")
        local mason_lspconfig = require("mason-lspconfig")
        mason.setup()
        mason_lspconfig.setup({
          ensure_installed = { "lua_ls", "nil_analyzer", "bashls" }, -- LSPs to ensure installed by Mason
        })
        mason_lspconfig.setup_handlers({
          function(server_name)
            -- Default handler: Setup LSP with capabilities
             local server_opts = {
                capabilities = capabilities -- Pass capabilities here too
             }
             -- Add specific settings if needed from a table, similar to below
             if server_name == "lua_ls" then
                 server_opts.settings = {
                    Lua = {
                        workspace = { checkThirdParty = false },
                        telemetry = { enable = false },
                    },
                 }
             end
            lspconfig[server_name].setup(server_opts)
          end,
          -- Example override for lua_ls (can be removed if default handler is sufficient)
          -- ["lua_ls"] = function()
          --   lspconfig.lua_ls.setup({
          --     capabilities = capabilities,
          --     settings = {
          --       Lua = {
          --         workspace = { checkThirdParty = false },
          --         telemetry = { enable = false },
          --       },
          --     },
          --   })
          -- end,
        })
      else
        -- Setup LSPs directly if using nixCats
        capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities) -- Add CMP capabilities only if Nix is managing CMP

        lspconfig.lua_ls.setup({
          capabilities = capabilities,
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
              diagnostics = { globals = { 'vim', 'nixCats' } }, -- Add nixCats global
            },
          },
        })
        lspconfig.nil_analyzer.setup({ capabilities = capabilities })
        lspconfig.bashls.setup({ capabilities = capabilities })
        -- Setup nixd if enabled by nixCats category
        if nixCats('lsp') then -- Assuming nixd is in the lsp category
            lspconfig.nixd.setup({ capabilities = capabilities })
        end
      end

      -- LSP Attach Autocommand (applies to both Mason and Nix setups)
      vim.api.nvim_create_autocmd('LspAttach', {
          group = vim.api.nvim_create_augroup('kickstart-lsp-attach-keymaps', { clear = true }),
          callback = function(event)
              local client = vim.lsp.get_client_by_id(event.data.client_id)
              local bufnr = event.buf

              -- Keymaps (consider moving to a separate on_attach function)
              vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer=bufnr, desc = "Hover symbol details" })
              vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer=bufnr, desc = "Go to definition" })
              vim.keymap.set("n", "gr", vim.lsp.buf.references, { buffer=bufnr, desc = "Go to references" })
              vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { buffer=bufnr, desc = "Code action" })

              -- Add inlay hints toggle if supported
              if client and client.server_capabilities.inlayHintProvider and vim.lsp.inlay_hint then
                  vim.keymap.set('n', '<leader>th', function()
                      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
                  end, { buffer = bufnr, desc = '[T]oggle Inlay [H]ints' })
              end
          end
      })

    end,
  },

  -- Example: Configure nvim-cmp (assuming relevant plugins are in nixCats config)
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets", -- Ensure snippets are loaded
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      -- Make snippet loading conditional? Or assume friendly-snippets is always wanted?
      -- If conditional, wrap this in an `if nixCats(...) or not isNixCats then ... end`
      require("luasnip.loaders.from_vscode").lazy_load() -- Load vscode snippets

      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },

  -- Add other plugin configurations here...

}, { -- Lazy options
  -- ui = { border = "rounded" }, -- Example lazy option
})

-- Set colorscheme
vim.cmd.colorscheme("tokyonight")

print("Neovim config loaded!")
