# Neovim Config

## Key Mappings

### General Mappings

| Action                    | Mappings                 |
| ------------------------- | ------------------------ |
| Leader key                | Space                    |
| Local                        |
| Exit insert mode          | `jk`, `<C-c>`            |
| Find file                 | `<leader>f`              |
| Find buffer               | `<leader>b`              |
| Recent files              | `<leader>r`              |
| Search (live grep)        | `<leader>\`              |
| File explorer             | `<leader>E`              |
| No highlight              | `<leader>hn`             |

### Window Management

| Action                     | Mapping                |
| -------------------------- | ---------------------- |
| Split window horizontally  | `ss`, `<leader>ws`     |
| Split window vertically    | `sv`, `<leader>wv`     |
| Go to the up window        | `sk`, `<leader>wk`     |
| Go to the down window      | `sj`, `<leader>wj`     |
| Go to the left window      | `sh`, `<leader>wh`     |
| Go to the right window     | `sl`, `<leader>wl`     |
| Switch window              | `sw`, `<leader>ww`     |
| Increase height            | `s+`, `<leader>w+`     |
| Decrease height            | `s-`, `<leader>w-`     |
| Increase width             | `s>`, `<leader>w>`     |
| Decrease width             | `s<`, `<leader>w<`     |
| Equal size                 | `s=`, `<leader>w=`     |
| Max out width              | `s|`, `<leader>w|`     |
| Close current window       | `sc`, `<leader>wc`     |
| Close other windows        | `so`, `<leader>wo`     |

### Buffers

| Actions         | Mappings    |
| --------------- | ----------- |
| Switch buffers  | `<leader>b` |
| Next buffer     | `]b`        |
| Previous buffer | `[b`        |

### Search

| Action                  | Mapping        |
| ----------------------- | -------------- |
| Search buffer           | `<leader>ss`   |
| Search project          | `<leader>sp`   |
| Search buffer symbols   | `<leader>sm`   |
| Search workspace symbols| `<leader>sM`   |
| Search treesitter symbols | `<leader>st` |

### Code Actions

| Action              | Mapping                  |
| ------------------- | ------------------------ |
| Code action         | `<leader>ca`, `,a`       |
| Format              | `<leader>cf`, `,f`       |
| Rename              | `<leader>cr`, `,r`       |
| Goto definition     | `<leader>cg`, `,g`       |
| Type definition     | `<leader>ct`, `,t`       |
| Show references     | `<leader>ce`, `,e`       |
| Show implementations| `<leader>ci`, `,i`       |
| Buffer diagnostics  | `<leader>cd`, `,d`       |
| Workspace diagnostics| `<leader>cD`, `,D`      |
| Incoming calls      | `<leader>ci`, `,i`       |
| Outgoing calls      | `<leader>co`, `,o`       |
| Quickfix            | `<leader>cq`, `,q`       |
| Hover doc           | `<leader>ch`, `,h`       |
| Signature help      | `<leader>cH`, `,H`       |

### Debugging

| Action                | Mapping             |
| --------------------- | ------------------- |
| Toggle Breakpoint     | `<leader>db`        |
| Breakpoint Condition  | `<leader>dB`        |
| Run/Continue          | `<leader>dc`        |
| Run with Args         | `<leader>da`        |
| Run to Cursor         | `<leader>dC`        |
| Go to Line (No Exec)  | `<leader>dg`        |
| Step Into             | `<leader>di`        |
| Step Over             | `<leader>dO`        |
| Step Out              | `<leader>do`        |
| Down                  | `<leader>dj`        |
| Up                    | `<leader>dk`        |
| Run Last              | `<leader>dl`        |
| Pause                 | `<leader>dP`        |
| Toggle REPL           | `<leader>dr`        |
| Session               | `<leader>ds`        |
| Terminate             | `<leader>dt`        |
| Widgets               | `<leader>dw`        |

### Git

| Action                     | Mapping          |
| -------------------------- | ---------------- |
| Next hunk                  | `<leader>gj`     |
| Prev hunk                  | `<leader>gk`     |
| Blame line                 | `<leader>gl`     |
| Blame buffer               | `<leader>gL`     |
| Preview hunk               | `<leader>gp`     |
| Reset hunk                 | `<leader>gr`     |
| Reset buffer               | `<leader>gR`     |
| Stage hunk                 | `<leader>gs`     |
| Undo stage hunk            | `<leader>gu`     |
| List files                 | `<leader>gf`     |
| Status                     | `<leader>go`     |
| Branches                   | `<leader>gb`     |
| Buffer commits             | `<leader>gc`     |
| Project commits            | `<leader>gC`     |
| Diff                       | `<leader>gd`     |

### Toggle/Test

| Action                | Mapping            |
| --------------------- | ------------------ |
| Toggle AutoSave       | `<leader>ts`       |
| Test current method   | `<leader>tm`       |
| Debug current method  | `<leader>td`       |
| Test current file     | `<leader>tf`       |
| Toggle test summary   | `<leader>tS`       |
| Toggle test output    | `<leader>to`       |
| Show test diagnostic  | `<leader>td`       |
| Hide test diagnostic  | `<leader>tD`       |

### Help

| Action                | Mapping            |
| --------------------- | ------------------ |
| No highlight          | `<leader>hn`       |
| Help tags             | `<leader>hh`       |
| Man pages             | `<leader>hm`       |
| Todos                 | `<leader>ht`       |
| Keymaps               | `<leader>hm`       |
| Registers             | `<leader>hr`       |
| Jumps                 | `<leader>hj`       |
| Commands              | `<leader>hx`       |
| Commands history      | `<leader>hX`       |

### AI

| Action                | Mapping            |
| --------------------- | ------------------ |
| Inline                | `<leader>ap`       |
| Actions               | `<leader>aa`       |
| Chat                  | `<leader>ac`       |

### Session Management

| Action                         | Mapping        |
| ------------------------------ | -------------- |
| Save session                   | `<leader>qs`   |
| Load current session           | `<leader>q.`   |
| Load last session              | `<leader>ql`   |
| Update plugins                 | `<leader>qu`   |
| Save                           | `<leader>qw`   |
| Save all                       | `<leader>qW`   |
| Quit                           | `<leader>qq`   |
| Save and quit all              | `<leader>qQ`   |

### Navigation

| Action                      | Mapping                       |
| --------------------------- | ----------------------------- |
| Next todo                   | `]t`                          |
| Previous todo               | `[t`                          |
| Next diagnostic             | `]d`                          |
| Previous diagnostic         | `[d`                          |
| Next method start           | `]m`                          |
| Previous method start       | `[m`                          |
| Next method end             | `]M`                          |
| Previous method end         | `[M`                          |
| Next class start            | `]c`                          |
| Previous class start        | `[c`                          |
| Next class end              | `]C`                          |
| Previous class end          | `[C`                          |


