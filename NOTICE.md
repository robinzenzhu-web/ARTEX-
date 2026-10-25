# Third-Party Notices

## dsh-purge — MIT License

- Source: https://github.com/kingcharleslzy-ai/dsh-purge
- Version referenced: 1.6.33
- License: MIT (Copyright (c) 2026 小刘)
- Upstream path: `skills/redteam/`

The following skill packages under `skills/` are derived from dsh-purge's
`skills/redteam/` directory:

```
active-scan          asset-correlation    browser-automation
chisel-tunnel        cn-proxy-pool        credential-attack
dir-bruteforce       fofa-recon           frp-tunnel
fscan-intranet       gogo-intranet        kimi-webbridge
lateral-movement     nuclei-scan          passive-recon
recon-pipeline       redteam-setup        shell-handler
suo5-tunnel          unauth-exploit       vps-reverse-shell
web-fingerprint      webshell-toolkit
```

### Modifications

1. Converted from bare `<name>.md` files to `<name>/SKILL.md` directory layout,
   matching the agentskills.io convention used by this repository.
2. Frontmatter preserved verbatim: `name`, `description`, `whenToUse` are
   consumed by `norma/skill`; `role` and `enabled` are retained as inert
   metadata (ignored by the loader).
3. Markdown body copied unchanged.

### MIT License

```
MIT License

Copyright (c) 2026 小刘

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
