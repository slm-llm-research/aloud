# B. MCP Ecosystem: How agentd Reaches Web Services by Voice

*Research date: 2026-10-31. Scope: integrating Model Context Protocol (MCP) servers into Aloud's `agentd` (Node 22, TypeScript, `@anthropic-ai/sdk` tool runner, Effect-typed ToolContracts). Every claim below is tied to a source in the list at the end. Where a source was third-party or a detail could not be confirmed, the text says so.*

---

## 0. TL;DR for the builder

1. **Use client-side MCP inside agentd, not the Anthropic API MCP connector, for anything that is not read-only.** The connector (`mcp_servers` + `mcp_toolset`) runs tool calls on Anthropic's side inside a single Messages call, so agentd's per-step approval cards cannot step in before a call runs. It also cannot reach local stdio servers. The connector is fine as an optional fast path for a pinned, allowlisted, read-only toolset. [S5]
2. **Target the 2026-07-28 spec, using the TypeScript SDK's v2 client package** (`@modelcontextprotocol/client`; v2.4.0 shipped 2026-10-23). v1.32.x is still maintained as a fallback. [S1][S2][S8]
3. **Write the OAuth 2.1 client yourself in agentd.** It is a native app with a loopback redirect, PKCE, the RFC 8707 `resource` parameter, RFC 9207 `iss` validation, a hosted Client ID Metadata Document (CIMD) with DCR as fallback, and `offline_access`. Store tokens in the macOS Keychain keyed by **issuer + resource**, with the Swift app acting as the Keychain broker. [S3][S4]
4. **Never trust tool annotations from a server.** Map `readOnlyHint`/`destructiveHint`/`openWorldHint` to Effects only in the direction of *more* caution. A local per-server policy manifest is the only thing that can relax a tool's Effect. Any unknown or changed tool defaults to **confirm**. [S7][S12]
5. **Finance stays read-only by construction.** Robinhood now has an **official Trading MCP** (`https://agent.robinhood.com/mcp/trading`, launched 2026-05-27; crypto added 2026-07-20). It can read all of your Robinhood accounts and trade in a separate Agentic account. agentd must mount only its read tools and block every order tool as `spend_money`. Use SnapTrade's read-scoped hosted MCP for multi-broker views. Do not use unofficial Robinhood scraping libraries. [S20][S21][S22][S24]
6. **Security controls that matter:** pin versions and tool-list hashes (rug-pull defence), tag untrusted content (prompt-injection defence), enforce per-server data boundaries (blocks cross-server exfiltration), require a click for `network_write` and `send_message`, never accept voice approval for send or spend, and sandbox stdio servers. [S12][S13][S14][S15]

---

## 1. MCP state of the art (late 2026)

### 1.1 Spec version: 2026-07-28 (current stable)

The **2026-07-28** revision is tagged "latest" and stable in the spec repo. Its release candidate was locked on 2026-05-21, and it is described as the largest revision since launch. [S1][S9]

| Area | 2025-11-25 (previous) | 2026-07-28 (current) | Impact on agentd |
|---|---|---|---|
| Lifecycle | `initialize`/`initialized` handshake, `Mcp-Session-Id` | **Stateless core.** Handshake and session header removed. `server/discover` and per-request `_meta` (protocol version, client capabilities) replace them. Gateways route on an `Mcp-Method` header. | Simpler reconnects. Auth must be sent on every HTTP request. [S9][S10] |
| Server→client requests | Over a held-open stream | **Multi Round-Trip Requests (MRTR).** The server returns `resultType: "input_required"` with an opaque `requestState`, and the client retries the call with its answers. | The elicitation UI becomes a *retry* loop in the tool runner. [S10] |
| Tool lists | `tools/list` + `list_changed` | `tools/list` may carry `ttlMs`, and clients may cache for that long. | Cache the list, then **hash and pin** it (see §4). [S9] |
| Extensions | Tasks experimental in core | **Official extensions:** Tasks (`io.modelcontextprotocol/tasks`), MCP Apps (server-rendered UI), Enterprise-Managed Authorization (EMA). | Tasks are useful for long jobs such as "summarize my week's email". [S10] |
| Deprecated (still functional, ≥12 months before removal) | — | **Roots, Sampling, Logging** | Don't build on Sampling. Folder boundaries move into server config. [S10] |
| Errors | missing resource `-32002` | `-32602` | Retry logic should catch both. [S9] |

Breaking-change commentary advises public servers to serve both versions on one endpoint for at least a quarter. agentd should negotiate down to 2025-11-25 for servers that haven't migrated. [S9]

### 1.2 Remote servers (Streamable HTTP)

Remote servers are now the default for SaaS: GitHub, Slack, Linear, Atlassian, Notion, Sentry, Vercel, Stripe, Google Workspace, Robinhood, SnapTrade and others all host endpoints (§2). Streamable HTTP is the standard remote transport. SSE survives as legacy, and many catalogues still list `/sse` URLs. [S5][S16] TypeScript SDK v1.32/v2.3 added same-origin-only HTTP redirects, request body size limits, and an opt-in `expectedResource` audience check. These are worth having on the client side. [S8]

### 1.3 Authorization (OAuth 2.1 profile)

What a 2026-07-28 client must do [S3][S4][S10][S12]:

- **Discovery:** follow `WWW-Authenticate` to the RFC 9728 Protected Resource Metadata, then to Authorization Server metadata (`/.well-known/oauth-authorization-server`, as clarified by SEP-2351).
- **Client registration preference order:** pre-registered credentials → **CIMD** (the client ID is an HTTPS URL to a JSON document the AS fetches) → DCR (deprecated but working) → ask the user. Native clients declare `application_type: "native"` (SEP-837).
- **PKCE plus the RFC 8707 `resource` parameter.** Servers must validate token audience. **Token passthrough is forbidden.**
- **`iss` validation (RFC 9207, SEP-2468):** exact string match before redeeming the code. A future revision makes this mandatory.
- **Refresh tokens through the `offline_access` scope** (SEP-2207). **Scope step-up** requests the union of the old and new scopes (SEP-2350).
- **Credential binding:** persisted credentials **must be keyed by issuer.** Storing them by MCP server URL alone is non-compliant (SEP-2352). Re-register if the AS changes.
- Real-world example: Home Assistant's MCP server already supports OAuth with PKCE and CIMD, and has no client secret. [S27]

### 1.4 Elicitation

- **Form mode:** flat JSON-Schema forms (string, number, boolean, enum). Servers **must not** request passwords, API keys, tokens or payment credentials this way.
- **URL mode:** an out-of-band browser flow for secrets, third-party OAuth and payments. The client **must** show the full URL with the domain highlighted, get consent, never pre-fetch it, and open it somewhere the client or LLM cannot inspect (the system browser, not a webview).
- Response actions are `accept`, `decline` or `cancel`. Under 2026-07-28 the answers come back on the *retried* request. [S11]

**For Aloud:** render elicitations as AgentPanel cards. Form fields can be filled by voice, but **submitting stays a click**. URL-mode requests open in the default browser through `NSWorkspace`, never through a shell (§4).

### 1.5 The official MCP Registry

- `registry.modelcontextprotocol.io`, API v0.1. It is still marked **preview** ("breaking changes or data resets may occur").
- It holds **metadata only** (`server.json`), pointing to npm, PyPI, NuGet, crates, OCI images, MCPB bundles, or `remotes` URLs.
- Namespaces are verified (`io.github.<user>/…` through GitHub sign-in; reverse-DNS such as `com.example/…` through DNS or HTTP proof). **Code is not scanned.** Security scanning is left to package registries and downstream marketplaces. [S6][S17]

**For Aloud:** use the registry for *discovery* in a "Connect a service" sheet. Trust comes only from Aloud's own curated allowlist (§4), never from being listed.

### 1.6 Three ways to wire MCP into a Claude app

| Option | How | Pros | Cons for agentd |
|---|---|---|---|
| **A. API MCP connector** | `mcp_servers: [{type:"url", url, name, authorization_token}]` + `tools: [{type:"mcp_toolset", mcp_server_name, default_config, configs}]`. Beta header `mcp-client-2025-11-20`, or `mcp-client-2026-09-15` for **tool-list pinning** (`mcp_tool_listing` blocks; you can pin `tools` in the toolset). | No client code. Anthropic runs the calls. Built-in allowlist and denylist. Pinning defeats mid-conversation tool changes. | Remote HTTPS only, **no stdio**, tools only (no resources or prompts). **Calls run server-side, so agentd cannot approve each call.** You still handle OAuth and refresh. **Not ZDR- or HIPAA-eligible.** [S5] |
| **B. Client-side MCP + SDK helpers** | `@modelcontextprotocol/sdk` (v1) or `@modelcontextprotocol/client` (v2) `Client` + transports. `mcpTools(tools, client)` from `@anthropic-ai/sdk/helpers/beta/mcp` feeds `toolRunner()`. `mcpMessages`, `mcpResourceToContent` and `mcpResourceToFile` handle prompts and resources. | Local **and** remote servers. Every call passes through agentd's policy engine. Supports resources, prompts and elicitation. | You implement OAuth, sandboxing and pinning yourself. [S7][S8] |
| **C. Claude Agent SDK** | `query({options:{mcpServers:{x:{command,args}|{type:"http",url,headers}}, allowedTools:["mcp__x__tool"]}})`. In-process `createSdkMcpServer()`. Tool search is on by default. | Mature host: reconnects, tool search, output limits (25k tokens / 50k chars spill to file). | Spawns the Claude Code runtime, a second agent loop beside agentd's. **The SDK does not run interactive OAuth.** It reports `needs-auth`, and you pass `Authorization` headers yourself. [S18] |

**Recommendation: Option B, owned by agentd.** Use Option A only for a "fast read" path where a pinned, read-only toolset (for example Exa search or Hugging Face) runs without a confirmation card. The `claude_code_task` tool can keep using the Agent SDK or CLI for dev workflows, where its native MCP config (`.mcp.json`) already works.

### 1.7 Proposed agentd MCP host design

```
agentd/
  mcp/
    registry.ts      // curated allowlist: id, transport, pinned version, toolset hash, policy
    host.ts          // spawns stdio clients, connects HTTP clients, health + reconnect
    oauth.ts         // OAuthClientProvider: loopback redirect, PKCE, CIMD/DCR, iss check
    policy.ts        // MCP tool -> ToolContract{effects}, overrides, deny patterns
    taint.ts         // untrusted-content tagging + per-server data boundaries
    elicit.ts        // MRTR input_required -> AgentPanel card -> retry
```

**Mounting**

- **Local stdio:** never use `npx -y pkg@latest`. Install each server into `~/Library/Application Support/Aloud/mcp/<id>/` with an **exact version plus a lockfile integrity hash**, and launch the resolved binary. Launch under a restrictive macOS sandbox profile (`sandbox-exec` with deny-default file access plus explicit allowed roots, or a container through Docker's MCP Toolkit/Gateway where available) with a minimal env. Inject secrets from the Keychain at spawn time only. [S12][S28]
- **Remote HTTP:** connect with a Streamable HTTP client transport. Send `MCP-Protocol-Version: 2026-07-28` and fall back to 2025-11-25. Accept HTTPS only, block private IP ranges during OAuth discovery (SSRF), validate redirects hop by hop, and keep the SDK's same-origin redirect behaviour. [S8][S12]

**OAuth and Keychain**

- Host a **CIMD JSON** (for example `https://aloud.dev/oauth/client.json`) with `client_name`, `redirect_uris: ["http://127.0.0.1/callback"]`, and `application_type: "native"`. Fall back to DCR. Some providers (Google Workspace, Slack) require a pre-registered client: Google needs a GCP OAuth client, and Slack needs a directory-published or internal app. [S3][S19][S25]
- agentd starts the flow and asks the Swift app over JSON-RPC to open the authorization URL in the default browser (`NSWorkspace.open`, no shell). A loopback listener catches the code. Validate `state` and `iss`, then redeem with the PKCE verifier and `resource`.
- **Keychain:** tokens are stored by the Swift side (`SecItemAdd`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, service `dev.aloud.mcp`, account `<issuer>|<resource>|<client_id>`). agentd fetches tokens over an authenticated RPC just in time and holds them only in memory. **Tokens never enter the model context, the audit log or env vars of remote servers.** Refresh happens proactively, and step-up requests the union of scopes.
- Request the minimum scopes. For example, Gmail `gmail.readonly` + `gmail.compose` (drafts), not full `mail.google.com`. [S19]

**Effect mapping (the core policy)**

The spec calls annotations *hints*, with defaults that assume the worst: `readOnlyHint=false`, `destructiveHint=true`, `idempotentHint=false`, `openWorldHint=true`. Clients should not trust annotations from untrusted servers. [S7][S12]

| Signal (evaluated in order; the strictest result wins) | Effect assigned | Policy |
|---|---|---|
| Local override in `registry.ts` (signed by you, per tool) | as declared | the override is the only thing that can *lower* a tool's Effect |
| Name/description matches `buy|sell|order|trade|transfer|pay|withdraw|deposit|checkout|purchase|subscribe` | `spend_money` | **BLOCKED** |
| Matches `delete|trash|remove|archive_all|purge|revoke|drop` or `destructiveHint: true` (and no override) | `delete_remote` (new) | **BLOCKED** by default; an override can downgrade it to confirm |
| Matches `send|reply|forward|post|publish|comment|dm|message|invite|share` | `send_message` | click approval, **never voice** |
| `readOnlyHint: true` **and** the server is in the trusted-publisher tier **and** the tool is in the pinned hash | `read_remote` (new) | auto; results tagged untrusted if `openWorldHint` is not false |
| `readOnlyHint: true` on a community or unpinned server | `read_remote` + `confirm_first_use` | one click per session |
| Anything else (no annotations, unknown, changed since pin) | `network_write` | **click approval** |
| Settings or device control (Home Assistant locks, garage, alarm) | `system_settings` / `physical_actuation` (new) | blocked or confirm, per entity class |

Add two Effects to the existing set: `read_remote` (auto) and `delete_remote` (blocked). Optionally add `physical_actuation` for smart-home devices. Present each approval card with the server's display name, its verified publisher, the tool name, and the **exact arguments**, rendered as human-readable text. For example: "Send to anna@…: 'Running 10 min late'".

---

## 2. Catalogue of MCP servers worth integrating

Legend: **Off** = official, run by the vendor; **Com** = community; **R** = remote HTTP; **L** = local stdio. "Tier" is the suggested agentd trust tier: T1 = vendor-hosted, read tools may auto-run; T2 = vendor package run locally; T3 = community, confirm everything, sandboxed.

### 2.1 Email, calendar, docs

| Server | Off/Com | R/L | Auth | Notes | Voice examples |
|---|---|---|---|---|---|
| **Google Workspace MCP** (Gmail `gmailmcp.googleapis.com/mcp/v1`, Calendar, Drive, Docs, Sheets, Slides, Chat, People) | Off (developer preview, rolling out from 2026-05-01) | R | OAuth 2.0 with your own GCP OAuth client; Gmail scopes `gmail.readonly` + `gmail.compose` | Gmail exposes `create_draft` and `search_threads`/`get_thread`/labels, with **no send tool**, which suits agentd's posture. Requires the Workspace Developer Preview Program. The docs don't confirm support for consumer Gmail accounts. [S19][S29] | "What did Priya email me about the offsite?" · "Draft a reply saying Thursday works." |
| taylorwilsdon `google_workspace_mcp` and similar | Com | L/R | your own Google OAuth client | Fallback for personal @gmail.com accounts. Tier T3. [S16] | "Find the PDF Mom sent last week." |
| **Microsoft Work IQ MCP** (Mail, Calendar, Teams via one endpoint) | Off | R | Entra ID; discovery through `/.well-known/oauth-protected-resource` | Tenant-oriented: it needs Work IQ enabled on the tenant, and the docs don't confirm consumer Outlook.com support. [S30] | "What's on my calendar after 3?" · "Summarize today's Teams chat with the infra team." |

### 2.2 Communication

| Server | Off/Com | R/L | Auth | Notes | Voice examples |
|---|---|---|---|---|---|
| **Slack MCP** `https://mcp.slack.com/mcp` | Off (GA Feb 2026) | R | OAuth user tokens with per-tool scopes; **directory or internal app required** | Search, history, send, canvases. Mark `send_message`/reactions as `send_message`. [S25] | "Any messages from my manager in the last hour?" · "Post 'deploy done' in #eval-infra." (click to approve) |
| korotovsky `slack-mcp-server` | Com | L | xoxp/xoxb/xoxc tokens | "Stealth" browser-token mode bypasses admin governance, so **don't use it**. [S25] | — |
| Discord servers | Com | L | bot token | Read-mostly. T3. | "What's new in the evals Discord?" |
| iMessage/Messages servers (read `chat.db`) | Com | L | Full Disk Access | High-sensitivity local data. Read-only only. **Never mount alongside an outbound-capable server in the same task** (§4). | "Did my wife text me back?" |

### 2.3 Developer tools

| Server | Off/Com | R/L | Auth | Voice examples |
|---|---|---|---|---|
| **GitHub** `https://api.githubcopilot.com/mcp/` | Off | R (also L) | OAuth 2.1 or PAT | "Which of my PRs are waiting on review?" · "Open an issue: flaky WER test on Parakeet." [S16][S18] |
| **GitLab MCP** (in the product, docs at `docs.gitlab.com/user/model_context_protocol/mcp_server`) | Off | R | OAuth | "Status of the latest pipeline on main?" [S31] |
| **Linear** `mcp.linear.app` | Off | R | OAuth 2.1 | "What's assigned to me this cycle?" · "Move INS-42 to In Review." [S16] |
| **Atlassian (Jira + Confluence)** `mcp.atlassian.com/v1/…` | Off | R | OAuth 2.1 | "Open Jira bugs for the booking agent?" [S16] |
| **Sentry** `mcp.sentry.dev` | Off | R | OAuth 2.1 | "Top new errors in agentd since yesterday?" [S16] |
| **Vercel** `mcp.vercel.com` | Off | R | OAuth 2.1 | "Did the docs site deploy succeed?" [S16] |
| **Cloudflare** (bindings, observability, docs…) | Off | R | OAuth 2.1 / open | "Show Worker error rate for the last hour." [S16] |
| **AWS MCP Server** (managed, GA 2026-05-06; plus awslabs local servers) | Off | R/L | IAM guardrails, CloudTrail | "How much did we spend on EC2 this month?" A single "call any AWS API" tool means every call is `network_write` unless allowlisted to `describe*`/`list*`/`get*`. [S32] |
| **Docker MCP Toolkit/Gateway** | Off | L | Docker Desktop | Also a *sandbox* for running other servers in containers. [S28] |
| **Kubernetes** (`containers/kubernetes-mcp-server`) | Com (Red Hat-maintained) | L | kubeconfig | "Why is the eval pod crash-looping?" Use a read-only context. |
| **Postgres** via DBHub (`@bytebase/dbhub`, `readonly = true`) | Com | L | DSN in env | "How many bench runs failed this week?" [S18] |
| **Playwright MCP** (Microsoft) / Chrome DevTools MCP (Google) | Off | L | none | "Open staging and screenshot the pricing page." Browser content is untrusted, so taint everything. |
| **Supabase / Neon / Prisma** | Off | R | OAuth 2.1 | "List tables in my Neon branch." [S16] |

### 2.4 Knowledge

| Server | Off/Com | R/L | Auth | Voice examples |
|---|---|---|---|---|
| **Notion** `mcp.notion.com` | Off | R | OAuth 2.1 | "Add 'Vancouver visa docs' to my Notion to-do page." [S16] |
| **Confluence** (Atlassian remote) | Off | R | OAuth 2.1 | "Find the runbook for the Acme sandbox." [S16] |
| **Obsidian** (vault servers or the Local REST API plugin) | Com | L | plugin API key | "What did I write about MRTR in my notes?" Aloud's own `read_file` over the vault folder may be enough. |

### 2.5 Productivity

| Server | Off/Com | R/L | Auth | Voice examples |
|---|---|---|---|---|
| **Todoist** (`Doist/todoist-ai`) | Off | R/L | OAuth / API token | "Add 'renew passport' for Friday." [S33] |
| **Asana** `mcp.asana.com` | Off | R | OAuth 2.1 | "What's due on the Q4 plan?" [S16] |
| **Things 3** (AppleScript/URL-scheme servers) | Com | L | none | "Add 'call daycare' to Today in Things." |
| **monday.com, Airtable, Box, Canva, Zapier** | Off | R | OAuth 2.1 / API key | Zapier is a meta-bridge: **treat every Zapier action as `network_write`.** [S16] |

### 2.6 Media and smart home

| Server | Off/Com | R/L | Auth | Voice examples |
|---|---|---|---|---|
| **Spotify** servers (Web API) | Com | L | Spotify OAuth (your own app) | "Play my focus playlist." · "What's this song?" Playback is a harmless, reversible write. Allow it after a first-use confirm. |
| **YouTube** (Data API / transcript servers) | Com | L | API key | "Summarize the transcript of the video in my front tab." |
| **Home Assistant MCP Server** (`/api/mcp`, built into HA) | Off | R (LAN) | OAuth 2.0 + PKCE + CIMD, admin users by default | Only entities exposed to Assist are visible. Prompts plus a live-context resource. [S27] Voice: "Turn off the nursery lights." · "Is the garage door closed?" Locks, garage and alarm count as `physical_actuation`: click required. |

### 2.7 Search, web and memory

| Server | Off/Com | R/L | Auth | Voice examples |
|---|---|---|---|---|
| **Brave Search** (`brave/brave-search-mcp-server`) | Off | L | API key | "Search for the 2026-07-28 MCP changelog." [S34] |
| **Exa** `mcp.exa.ai/mcp` | Off | R | open / API key | "Find recent papers on streaming ASR fidelity." [S16] |
| **Perplexity** (`perplexityai/modelcontextprotocol`) | Off | L | API key | "Ask Perplexity what changed in Canada's IEC rules." [S34] |
| **Firecrawl** | Off | L/R | API key | "Scrape this pricing page into a table." |
| **Memory** (`modelcontextprotocol/servers` knowledge-graph reference) | Off (reference) | L | none | "Remember that my Acme sandbox key rotates monthly." Prefer agentd's own memory store. |
| **Hugging Face** `hf.co/mcp` | Off | R | open / HF token | "What are today's trending ASR models?" [S16] |

### 2.8 Payments and travel

| Server | Off/Com | R/L | Auth | Notes / Voice |
|---|---|---|---|---|
| **Stripe** `mcp.stripe.com` | Off | R | OAuth 2.1 / restricted API key | Use a **restricted read-only key**. Refunds and charges are `spend_money`, so they are blocked. "How much revenue did the course site make this week?" [S16] |
| **PayPal, Square, Ramp** | Off | R | OAuth 2.1 | Read-only reporting only. [S16] |
| **Expedia** (B2B MCP; `expedia-travel-recommendations-mcp`) | Off | R/L | partner API key | "Find hotels near Granville Island for Aug 20–23." Booking is `spend_money`, so it is blocked. [S35] |
| Turkish Airlines, Ferryhopper, Kiwi-style flight search | Off/Com | R | OAuth / open | Search only. [S16] |

---

## 3. Finance: a read-only design

### 3.1 What exists (verified)

| Provider | Official API/MCP in 2026? | Read | Trade | Auth | Source |
|---|---|---|---|---|---|
| **Robinhood: Trading MCP** | **Yes.** `https://agent.robinhood.com/mcp/trading`. Launched 2026-05-27 for equities; options and crypto came later (crypto announced 2026-07-20). | Read access to **all** your Robinhood accounts: positions, balances, transactions, order history, account numbers. Tool groups: account/portfolio, watchlist, market data, equities, options, crypto. | Only in a separate **Robinhood Agentic (MCP) account** you fund. It can trade without confirmation if you tell it to. Push notification per trade. Robinhood says customers bear all risk. | Authenticates through the AI platform. Support pages don't name the protocol; it is OAuth in practice for Claude Code (`/mcp` → authenticate). **No documented read-only mode.** | [S20][S21][S22][S23] |
| **Robinhood Crypto Trading API** | Yes (v1/v2) | accounts, holdings, orders, products, quotes | crypto orders | API key created in web classic **with selectable actions**, so you can make a read-only key | [S24] |
| **SnapTrade MCP** `https://mcp.snaptrade.com/mcp` | Yes (SnapTrade Personal, free) | 18 tools: connections, balances, positions, balance history, orders, activities | **None.** "Cannot place trades, move money, or change account settings" | OAuth 2.0 + PKCE, `read` scope; the agent never sees brokerage credentials | [S36] |
| **Plaid** | The Plaid MCP (`api.dashboard.plaid.com/mcp`) is a *developer dashboard* tool, not end-user data. Investments data comes from your own Plaid app (`/investments/holdings/get`). | holdings, transactions | none | Plaid developer account, Link | [S16][S37] |
| **Alpaca MCP v2** (2026-04-09) | Yes, official, local (61 tools) | market data, positions | yes (paper or live) | API keys; `ALPACA_TOOLSETS` restricts it to e.g. `stock-data,crypto-data`. No read-only mode is documented. | [S38] |
| **Schwab Trader API** | Individual developer API (developer.schwab.com). No first-party MCP; community `schwab-mcp` servers exist. | accounts, positions, quotes | yes | OAuth; refresh tokens expire about every 7 days (per community docs) | [S39][S40] |
| **Fidelity** | **No** public retail API or first-party AI connector | through aggregators (SnapTrade/Plaid) | — | — | [S40] |
| **Interactive Brokers** | Official connector that reads and drafts orders; the user submits them | yes | user-submitted | — | [S40] (third-party comparison) |
| **Coinbase for Agents** `https://agents.coinbase.com/mcp` (Sep 2026) | Yes, remote, plus the `@coinbase/coinbase-cli` local option | portfolios, balances, products | yes (portfolio-scoped); x402 payments capped at 5 USDC each | OAuth (remote) / CDP key (CLI). No read-only mode described. | [S41] (third-party write-up of CDP docs; verify) |
| **Market data** (Alpha Vantage, Yahoo Finance community servers, Morningstar remote MCP, Financial Datasets) | Mixed | quotes, fundamentals, news | — | API keys / OAuth | [S16][S42] |

### 3.2 Recommended architecture: "finance-ro"

```
Voice: "How are my investments doing?" / "What moved my portfolio today?"
   │
agentd ── finance-ro policy bundle ──┬─ SnapTrade MCP (read scope)       [primary, multi-broker]
                                     ├─ Robinhood Trading MCP            [READ tools only; order tools hard-denied]
                                     ├─ Robinhood Crypto API key         [read-only actions only, local wrapper]
                                     └─ Market-data MCP (quotes/news)    [no account data ever sent here]
```

1. **Mount positions sources with an explicit allowlist, not a denylist.** For Robinhood, enable only tool names in the account/portfolio, watchlist and market-data groups. Pin the tool-list hash. Any new tool that appears (for example a new `place_*` tool) is **disabled until you review it**. Separately, the `spend_money` name heuristic blocks any `order|buy|sell|trade|transfer` tool even if someone adds it to the allowlist by mistake.
2. **Don't create the Robinhood Agentic account.** If the OAuth flow pushes you to open one, leave it unfunded. A $0 account plus agentd's block gives two independent layers. (Robinhood's docs require the MCP account for connection, so treat this as a residual risk to accept knowingly.) [S21]
3. **Prefer SnapTrade for the "all brokers" view.** It is read-only at the server, so the guarantee doesn't depend on agentd's policy. Check `list_supported_brokerages` for Robinhood, Fidelity and Schwab coverage.
4. **Compute locally.** "What moved my portfolio today" = Σ(position qty × (last − prev close)), ranked by contribution, joined with a market-data news lookup. Send **only tickers** to the market-data server, never quantities or account IDs. That boundary is the per-server data boundary in action.
5. **Spoken output hygiene:** speak percentages and rounded dollar amounts. Never speak or paste account numbers. Redact them in the audit log.
6. **Effects:** all finance reads are `read_remote` + `sensitive_financial`. A visible HUD badge shows "finance data in context", and while that flag is set, `send_message` and `network_write` to any *other* server need an extra confirmation (anti-exfiltration).

### 3.3 Why trading must stay blocked (`spend_money`)

- **Irreversible and fast.** Robinhood itself warns that agent strategies "can act quickly and may be hard to stop in real time" and that customers bear all the risk. [S20][S22]
- **STT error surface.** "Buy fifteen" vs "fifty", "sell Meta" vs "sell metal". Aloud's fidelity guardrail lowers that risk but cannot remove it, and a quantity mistake costs real money.
- **Prompt injection through market content.** News, filings and watchlist notes are attacker-controllable text. A data-borne injection like the GitHub MCP exploit could turn into an order. [S13]
- **Voice approval is spoofable** (other people talking, TTS from a video playing in the background). Aloud's rule "no voice approval for send/spend/delete" must hold here without exception.
- **Regulatory and accountability exposure.** Robinhood states it doesn't supervise or audit customers' agents, and dispute resolution compares your instructions with the agent's actions. An open-source portfolio project shouldn't ship a trading path. [S22]

### 3.4 Unofficial Robinhood libraries (robin_stocks and similar)

These libraries reverse-engineer private endpoints with your username, password and MFA. Risks: **possible ToS violation leading to account restriction or termination**, possible exposure under computer-misuse law (CFAA arguments), silent breakage when endpoints change, and incorrect position data. They also put full-account credentials (not a scoped token) on disk. [S43] Now that an official MCP and the Crypto API exist, there is no reason to use them. **Aloud should refuse to ship or recommend them.**

---

## 4. Security: threats and agentd mitigations

### 4.1 Threat catalogue (with real incidents)

| Threat | What happened / how it works | Source |
|---|---|---|
| **Tool poisoning** | Hidden instructions in tool *descriptions* enter the model's context as trusted (Invariant Labs, Apr 2025). | [S14] |
| **Cross-server exfiltration ("shadowing")** | A malicious trivia server's description made the agent read WhatsApp history through a *legitimate* whatsapp-mcp server and send it out. | [S14] |
| **Prompt injection via tool results** | A malicious public GitHub issue made the agent (official GitHub MCP, "Always Allow" on) copy private-repo data, including salary and relocation plans, into a public PR (May 2025). Willison's "lethal trifecta": private data + untrusted content + an exfiltration channel. | [S13][S15] |
| **Rug pull / supply chain** | `postmark-mcp` shipped 15 clean versions, then v1.0.16 (2025-09-17) silently BCC'd every email to the attacker. About 1,500 weekly downloads. | [S14][S44] |
| **Config swap** | Cursor "MCPoison" CVE-2025-54136: an approved MCP config was swapped later without re-approval. | [S14] |
| **Server bugs → RCE / path escape** | Anthropic reference servers: Filesystem "EscapeRoute" CVE-2025-53109/53110; mcp-server-git chain CVE-2025-68143/4/5. Client-side: `mcp-remote` CVE-2025-6514 (CVSS 9.6, shell injection). | [S14] |
| **Confused deputy (OAuth)** | An MCP proxy using a static client ID plus DCR plus a consent cookie lets an attacker's registered client get a code without consent. Spec: per-client consent, exact redirect matching, single-use `state`. | [S12] |
| **SSRF during OAuth discovery** | A malicious server points `resource_metadata` at `169.254.169.254` or `localhost` services. | [S12] |
| **Malicious auth URLs** | `javascript:` or shell-injected authorization URLs lead to XSS or RCE when opened through a shell. | [S12] |
| **Token passthrough / over-broad scopes** | Forbidden by spec. Broad tokens widen the blast radius. | [S12] |

### 4.2 Concrete mitigations for agentd

**Supply chain and rug-pull**

1. **Curated allowlist only** (`mcp/registry.ts`): server id, publisher tier, transport, **exact version + integrity hash** (stdio) or **URL + expected issuer** (remote). The UI can *discover* from the official registry, but connecting a server that isn't on the list requires an explicit "add untrusted server" flow. That flow shows the full launch command (a spec MUST for one-click local config). [S6][S12]
2. **Tool-list pinning:** store SHA-256 of the canonical JSON `{name, description, inputSchema, annotations}` for every approved tool. On every `tools/list`, or when `ttlMs` expires, diff against the pin. **Changed descriptions or schemas, and new tools, are disabled until the user re-approves with a visible diff.** This copies `mcp-client-2026-09-15` pinning on the client side. [S5]
3. **No auto-updates.** Version bumps go through a review PR in your dotfiles or settings, and diffs of tool descriptions are shown.

**Prompt injection and untrusted content**

4. **Tag all tool results** before they reach the model: `<untrusted source="mcp:slack" tool="search" id="r17">…</untrusted>`. The system prompt states that text inside these tags is data, never instructions. Strip or neutralize invisible Unicode and markdown image links (a common exfiltration trick) in results.
5. **Taint tracking:** each turn carries a set of `{servers touched, sensitivity labels}`. Once untrusted content from server A is in context, any `network_write` or `send_message` to server B, or `open_url` to a new domain, needs a click *and* the card shows "this action follows content from A".
6. **Lethal-trifecta breaker:** a task may hold *at most two* of {private data, untrusted content, outbound channel} without an explicit user override. For example, iMessage read + web search + Slack send in one task raises a "split this task" prompt. [S15]

**Per-server data boundaries**

7. Each server declares the data classes it may *receive* in arguments (`finance-ro`: none outbound; market data: tickers only; Slack: text the user dictated). The policy engine inspects tool arguments for values drawn from other servers' results (string-overlap and regex detectors for emails, account numbers, API-key shapes) and blocks or escalates when a value crosses a boundary.

**Approvals**

8. Effects → policy as in §1.7: `read_remote` auto (trusted tier only); `network_write` and `send_message` require a **click**, with the exact arguments rendered; `spend_money`, `delete_remote` and `system_settings` are **blocked**; `physical_actuation` is a click.
9. **No voice approval for send, spend or delete**, ever. Voice may approve only low-risk, reversible actions (playback, creating a draft, adding a to-do).
10. **Approval fatigue control:** batch similar confirmations ("send these 3 drafts?" still shows each one). Never offer "always allow" for `send_message`; the GitHub incident depended on "Always Allow". [S13]
11. Keep the 2-minute approval timeout and kill switch. Extend the kill switch to **revoke**: drop all MCP connections and wipe in-memory tokens.

**OAuth hardening**

12. Native-app OAuth with PKCE, `resource`, exact `iss` check, `state` bound to the flow, single-use, 10-minute TTL. Credentials are keyed by issuer. HTTPS-only discovery, with private-IP and link-local blocking and per-hop redirect validation. Open URLs only via `NSWorkspace` after scheme validation (`https` only). Never pass a token to a server it wasn't issued for. [S3][S4][S12]

**Local process isolation**

13. Run stdio servers in a sandbox: a deny-default file profile allowing only the server's own directory and declared roots, no access to `~/.ssh`, `~/Library/Keychains` or browser profiles, and network egress restricted to the vendor's API host where possible. Use Docker MCP Gateway containers for T3 servers. Validate and canonicalize any path arguments agentd itself forwards. [S12][S14][S28]

**Audit**

14. Extend the JSONL audit log with: server id, version/pin hash, tool, Effect, argument digest (secrets redacted), taint set, approver (click/voice/auto), latency, and result size. This also feeds the bench harness: add MCP scenarios, including injection test cases (a poisoned issue, a poisoned email), to the 37-scenario suite.

---

## 5. Build order (suggested)

1. `mcp/host.ts` + `policy.ts` with **stdio only**: Brave Search and the GitHub local server, read tools auto, everything else click.
2. `oauth.ts` + Keychain broker, then GitHub remote, Linear and Notion (all standard OAuth 2.1).
3. Pinning, the taint layer and injection bench scenarios.
4. Google Workspace (Gmail drafts, Calendar reads), Slack (read + click-to-send).
5. Home Assistant (LAN, CIMD) as the "wow" demo: "Goodnight" turns off lights and reports which doors are open.
6. `finance-ro` bundle (SnapTrade + Robinhood read tools), with a published threat model in `research/`.

---

## Sources

- [S1] MCP spec release 2026-07-28: https://github.com/modelcontextprotocol/specification/releases/tag/2026-07-28
- [S2] releases.sh, MCP specification tracker: https://releases.sh/modelcontextprotocol/mcp-specification.md
- [S3] SSOJet, MCP Authorization Spec 2026-07-28, what changed: https://ssojet.com/blog/mcp-authorization-spec-2026-07-28-what-changed
- [S4] MojoAuth, How MCP authorization works (OAuth 2.1, resource indicators): https://mojoauth.com/blog/how-mcp-authorization-actually-works-oauth-2-1-resource-servers-and-resource-indicators
- [S5] Anthropic, MCP connector docs: https://platform.claude.com/docs/en/agents-and-tools/mcp-connector
- [S6] MCPBundles, What is the MCP Registry: https://www.mcpbundles.com/guides/mcp-registry
- [S7] Anthropic TypeScript SDK docs (MCP helpers, toolRunner): https://platform.claude.com/docs/en/cli-sdks-libraries/sdks/typescript
- [S8] releases.sh, MCP TypeScript SDK releases: https://releases.sh/modelcontextprotocol/mcp-typescript-sdk ; v2 client API: https://ts.sdk.modelcontextprotocol.io/v2/api/@modelcontextprotocol/client/
- [S9] DEV, Why MCP 2026-07-28 drops sessions: https://dev.to/rabinarayanpatra/why-mcp-2026-07-28-spec-drops-sessions-and-goes-stateless-1gd ; DevelopersDigest breaking changes: https://www.developersdigest.tech/blog/mcp-2026-07-28-breaking-changes
- [S10] Descope, July 2026 MCP revision: https://www.descope.com/blog/post/july-2026-mcp-revision
- [S11] MCP spec 2026-07-28, Elicitation: https://modelcontextprotocol.io/specification/2026-07-28/client/elicitation
- [S12] MCP Security Best Practices (2025-11-25): https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices
- [S13] Invariant Labs, GitHub MCP exploited: https://invariantlabs.ai/blog/mcp-github-vulnerability
- [S14] DEV, State of MCP Security 2026: https://dev.to/luckypipewrench/the-state-of-mcp-security-2026-incidents-attack-patterns-and-defense-coverage-2h45 ; CSA research note on tool poisoning: https://labs.cloudsecurityalliance.org/research/csa-research-note-mcp-tool-poisoning-ai-agent-exfiltration-2/
- [S15] Simon Willison, The lethal trifecta: https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/
- [S16] awesome-remote-mcp-servers (URLs and auth types): https://github.com/jaw9c/awesome-remote-mcp-servers/ ; Anthropic remote MCP servers list: https://docs.claude.com/en/docs/agents-and-tools/remote-mcp-servers
- [S17] MCP Registry preview announcement: https://blog.modelcontextprotocol.io/posts/2025-09-08-mcp-registry-preview/
- [S18] Claude Agent SDK, MCP: https://code.claude.com/docs/en/agent-sdk/mcp
- [S19] Google, Configure the Google Workspace MCP servers: https://developers.google.com/workspace/guides/configure-mcp-servers
- [S20] Genfinity, Robinhood agentic trading adds crypto: https://genfinity.io/2026/07/21/robinhood-agentic-trading-crypto-ai-agents/
- [S21] Robinhood, Onboarding an external agent: https://robinhood.com/us/en/support/articles/onboarding-an-external-agent/ ; Agentic Trading overview: https://www.robinhood.com/us/en/support/articles/agentic-trading-overview/
- [S22] InvestmentNews, Robinhood AI trading launch: https://www.investmentnews.com/fintech/robinhood-just-made-a-bold-move-into-ai-powered-trading-for-the-retail-market/266771
- [S23] Robinhood newsroom, Robinhood is now open to agents (2026-05-27): https://robinhood.com/newsroom/robinhood-is-now-open-to-agents ; TechCrunch: https://techcrunch.com/2026/05/27/robinhood-now-lets-your-ai-agents-trade-stocks/
- [S24] Robinhood, Crypto Trading API: https://robinhood.com/us/en/support/articles/crypto-api/
- [S25] Gamut, Slack MCP guide (official + community): https://gamut.so/blog/slack-mcp-server-guide ; Slack docs: https://docs.slack.dev/ai/slackbot-mcp-client/
- [S27] Home Assistant, MCP Server integration: https://www.home-assistant.io/integrations/mcp_server
- [S28] Docker MCP Toolkit docs: https://docs.docker.com/ai/mcp-catalog-and-toolkit/toolkit/
- [S29] Google Workspace Updates, Agent tools and security updates (May 2026): https://workspaceupdates.googleblog.com/2026/05/agent-tools-and-security-updates-for-workspace-developers.html
- [S30] Microsoft Learn, Work IQ MCP overview: https://learn.microsoft.com/en-us/microsoft-365-copilot/extensibility/work-iq/mcp/overview
- [S31] GitLab MCP server docs: https://docs.gitlab.com/user/gitlab_duo/model_context_protocol/mcp_server
- [S32] AWS, AWS MCP Server GA (May 2026): https://aws.amazon.com/about-aws/whats-new/2026/05/aws-mcp-server/
- [S33] Todoist official MCP (Doist todoist-ai): https://www.developersdigest.tech/mcp-servers/todoist
- [S34] Brave Search MCP server listing: https://lobehub.com/de/mcp/brave-brave-search-mcp-server ; Perplexity MCP listing: https://lobehub.com/es/mcp/perplexityai-modelcontextprotocol
- [S35] AltexSoft, Expedia to launch MCP: https://www.altexsoft.com/travel-industry-news/expedia-to-launch-mcp-as-b2b-revenue-rises-25-percent/ ; PyPI expedia-travel-recommendations-mcp: https://pypi.org/project/expedia-travel-recommendations-mcp/
- [S36] SnapTrade MCP server docs: https://docs.snaptrade.com/docs/mcp-server
- [S37] Plaid Investments docs: https://plaid.com/docs/investments/
- [S38] Alpaca, MCP Server V2: https://alpaca.markets/blog/alpaca-launches-mcp-server-v2/ ; repo: https://github.com/alpacahq/alpaca-mcp-server
- [S39] schwab-mcp (Go): https://pkg.go.dev/github.com/itsmostafa/schwab-mcp@v0.2.3
- [S40] Walnut, MCP connectors for brokerages compared (third-party, vendor-authored): https://walnutinvest.com/resources/mcp-connectors-for-brokerages-compared
- [S41] StablecoinInsider, Coinbase for Agents with MCP and CLI: https://stablecoininsider.org/how-to-use-coinbase-for-agents-with-mcp-and-cli/
- [S42] Walnut, Best MCP servers for stock trading and market data (2026): https://walnutinvest.com/resources/best-mcp-servers-for-stock-trading
- [S43] TradersPost, Does Robinhood have an API? (vendor-authored): https://blog.traderspost.io/article/does-robinhood-have-an-api
- [S44] The Register, postmark-mcp server code hijacked: https://www.theregister.com/2025/09/29/postmark_mcp_server_code_hijacked/ ; CSO Online: https://csoonline.com/article/4064009/trust-in-mcp-takes-first-in-the-wild-hit-via-squatted-postmark-connector.html
