# llama-service.nvim

On-demand local llama-server shared between Neovim processes. Requiring the
module and `setup(opts)` start no process. The host's Minuet integration calls
`ensure()` only with a UI attached and an eligible editing buffer.

`setup` accepts partial `port`, `dir`, `server`, `args`, `model`, `recheck` values.
`args` is an argv list and replaces defaults, including an empty list. `dir` is
runtime storage, not the model path. `config` is the effective service table;
`ensure`, `ready`, `url(path)`, `log`, `release` are the existing service API.
The bundled `scripts/llama-supervise` owns process registration, lock, startup,
shutdown and crash handling. It stops the server after the last live Nvim leaves.

Editable host preferences live in `lua/config/completion.lua`; they are
independent of AI chat providers and HTTP key profiles. Native agent providers
have no dependency on this service. Offline fixtures exercise the supervisor
without loading model weights.
