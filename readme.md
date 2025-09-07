
# hlpatterns: Highlight User-Defined Patterns in Neovim

hlpatterns is a Neovim plugin designed to enhance your coding experience by allowing you to highlight custom patterns directly in your code. Whether you're debugging, refactoring, or simply want to emphasize specific parts of your code, hlpatterns provides a seamless way to achieve this.
Features

    Custom Pattern Highlighting: Easily define and highlight patterns that matter to you.
    Dynamic Updates: Highlights update in real-time as you edit your code.
    Flexible Configuration: Customize highlight colors, priorities, and more.

# Installation

To install hlpatterns, you can use your preferred plugin manager. Here are some examples:
Using vim-plug

Add the following line to your init.vim or init.lua:

Plug 'your-github-username/hlpatterns'

Then, run :PlugInstall in Neovim.
Using packer.nvim

Add the following to your packer configuration:

use 'your-github-username/hlpatterns'

Then, run :PackerSync in Neovim.
Configuration

hlpatterns comes with defaults, but you can customize it to fit your needs. Here's an example configuration:

require('hlpatterns').setup()

## Default configuration

The default configuration is defined below. The following content doesn't need to be copied in the setup function.

```
	min_color = min_color,
	max_color = max_color,
	highlight_priority = 100,
	fgcolor = "FFFFFF",
	min_red_color = min_color,
	max_red_color = max_color,
	min_green_color = min_color,
	max_green_color = max_color,
	min_blue_color = min_color,
	max_blue_color = max_color,

	group_name = "custom",

	highlight_pattern_keymap = nil
	delete_all_highlight_keymap = nil,
	highlight_selected_keymap = nil,
```

The default configuration doesn't create keymaps to highlight pattern, If you want, you can add it to the configuration by settings the following values: 
- `highlight_pattern_keymap`
- `highlight_pattern_keymap`
- `delete_all_highlight_keymap`

Usage

Several functions are available to the user : 
- `HlpatternsAdd()` to highlight a user-defined pattern
- `HlpatternsDeleteAll()` to delete all highlights
- `HlpatternDelete()` to delete custom highlight (no argument will remove all highlight)
- `HlpatternsList()` to list all highlights

# Contributing

Contributions are welcome! If you have ideas for new features, improvements, or bug fixes, feel free to open an issue or submit a pull request on the GitHub repository.
License

# hlpatterns is licensed under the MIT License. See the LICENSE file for more details.

# todolist
~~0. mAKE PLUGIN WORK !~~
~~1. Add variable to handles keymaps (N and V)~~
~~2. Give access to the list of highlight~~
~~3. Add a way to remove highlight~~
~~4. Add the possibility to add custom color~~
5. Revert light theme dark theme
6. Add fixed color
7. Add fixed color in config
~~8. Add labels~~

