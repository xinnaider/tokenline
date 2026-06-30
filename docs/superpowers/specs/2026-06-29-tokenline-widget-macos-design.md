# tokenline — widget macOS multi-conta (design)

Data: 2026-06-29 · Branch: `feat/macos-widget`

## Objetivo

Um widget de **menu bar macOS** que mostra, lado a lado, o uso de **N contas
Claude** (o autor usa 3, cada uma num `CLAUDE_CONFIG_DIR` separado). Mesma alma
da statusline `tokenline.sh` — modelo, contexto, cache, economia de tokens,
saving %, rate-limit 5h/7d — mas **agregado por conta**, sempre visível na barra.

Layout escolhido: **B "tudo denso"** — cada conta exibe tudo de uma vez num
bloco compacto. Ícone recolhido da barra mostra o **pior 5h %** entre as contas.

## Restrição central que molda tudo

`rate_limits.{five_hour,seven_day}` e a economia per-turn **só existem no payload
de stdin da statusline** (uma vez por segundo, por sessão). Não estão nos
transcripts nem em hooks. Logo a captura **tem que pegar carona na statusline** —
é o único ponto onde o dado nasce. O widget não pode sentar no stdin de cada CLI;
precisa de um store compartilhado persistido que a statusline alimenta.

## Abordagem (A): statusline como sensor + app leitor

```
sessão (CLAUDE_CONFIG_DIR=trabalho) ──┐
sessão (CLAUDE_CONFIG_DIR=pessoal)  ──┤  tokenline.sh (render normal)
sessão (CLAUDE_CONFIG_DIR=cliente)  ──┘        │
                                               │ writer opt-in (TOKENLINE_WIDGET=1)
                                               ▼
                  ~/Library/Application Support/tokenline/widget/<conta>.json  (0700, atômico)
                                               │
                                               │ DispatchSource (FS) + Timer ~5s
                                               ▼
                        App SwiftUI MenuBarExtra (lê N json, agrega, renderiza)
                                               │
                            barra: pior 5h%  ·  dropdown: 1 bloco denso por conta
```

Três unidades, cada uma com um propósito e interface clara:

### 1. Writer (dentro de `tokenline.sh`)

- **Opt-in.** Default OFF. Só age com `TOKENLINE_WIDGET=1`. Sem a flag, zero
  mudança de comportamento. Dir configurável via `TOKENLINE_WIDGET_DIR`
  (default `~/Library/Application Support/tokenline/widget`).
- **Nunca quebra a statusline.** O write roda isolado, depois da linha já
  impressa: `( _write_widget_snapshot ) 2>/dev/null || true`. Qualquer falha
  (jq, disco cheio, permissão) é engolida. Hot path nunca depende dele.
- **Throttle.** Escreve só se o conteúdo derivado mudou **ou** ≥ N s desde o
  último write (default 5s). Evita churn de disco a 1 Hz × 3 sessões.
- **Chave de conta** = `basename "$CLAUDE_CONFIG_DIR"` (fallback `default` se
  unset). É o identificador estável da conta (o payload não traz email/conta).
- **Escrita atômica:** grava em `<conta>.json.tmp` e `mv` por cima.
- **Só contadores derivados.** Nunca o payload bruto de stdin. Reusa as
  variáveis que `tokenline.sh` já computou (`model`, `used_pct`, `tokens_used`,
  `rl_5h_*`, `rl_7d_*`, econ read/write/new/output, saving, cache state/TTL).
- **Gasto cumulativo (sessão):** o writer mantém um contador de tokens por
  sessão (soma `new+output` a cada turno novo, detectado por mudança em
  `tokens_used`, espelhando o cache `lasttokens-<session>` que já existe).
  Reseta quando `session_id` muda. "Gasto hoje" exigiria histórico diário
  persistido (o snapshot é sobrescrito por conta) → fora do v1, vira futuro.

#### Schema do snapshot (`<conta>.json`)

```json
{
  "schema": 1,
  "account_key": "trabalho",
  "session_id": "abc123",
  "model": "Opus 4.8",
  "context": { "used_pct": 62, "size": 200000, "tokens_used": 124000 },
  "cache": { "state": "HOT", "ttl_label": "5m", "ttl_s": 247 },
  "econ": { "read": 18000, "write": 2100, "new": 3400, "output": 1200, "eq": 24000 },
  "saving_pct": 71,
  "rate": {
    "five_hour": { "pct": 95, "resets_at": "2026-06-29T17:05:00Z" },
    "seven_day": { "pct": 88, "resets_at": "2026-07-02T00:00:00Z" }
  },
  "spend": { "session_tokens": 1240000 },
  "updated_at": 1782783346
}
```

Gasto em **tokens** (contas são assinatura Max/Pro). `$` real exigiria tabela de
preço por modelo e só faz sentido para conta API-key → fora do v1.

### 2. Store de snapshots

- `~/Library/Application Support/tokenline/widget/`, `0700`. Um JSON por conta.
- **Persistente de propósito** (sobrevive entre sessões → mostra último-conhecido
  quando nenhuma sessão da conta está viva). Difere do cache efêmero per-turn que
  vive em `$XDG_RUNTIME_DIR`.
- **Reconciliação com a hard constraint** "never write session input to disk":
  gravamos **apenas métricas derivadas** (percentuais, contadores, labels), nunca
  o payload de sessão bruto. É uma exceção explícita e revisada ao default
  "in-memory only", justificada porque o produto exige um ponto de agregação.

### 3. App menu bar (leitor)

- **SwiftUI `MenuBarExtra`**, macOS 13+ (Ventura). **Não-sandboxed** (precisa ler
  o dir escrito pelo bash; sandbox isolaria o container). `LSUIElement = YES`
  (agente, sem ícone no Dock).
- **Atualização:** `DispatchSource` (vnode) no dir p/ update instantâneo +
  `Timer` ~5s de fallback (recalcula staleness mesmo sem novo write).
- **Parsing tolerante:** `Codable` por arquivo; json ausente/parcial/corrompido →
  pula a conta e mostra chip de erro. Nunca crasha por snapshot malformado.
- **Barra recolhida:** pior `five_hour.pct` entre as contas, colorido
  (verde <50 / âmbar 50–85 / vermelho >85). Ex.: `95%`.
- **Dropdown (B denso):** um bloco por conta, ordenado por `five_hour.pct` desc
  (mais apertada no topo). Cada bloco:
  - linha 1: **label** (de `labels.json`, fallback `account_key`) · badge cache
    (HOT/COLD) · **modelo** à direita
  - barra 5h colorida
  - meta: `5h pct` · `7d pct` · `ctx pct` · `saving pct` · `econ r/w/o` ·
    `gasto tokens`
  - **idle:** se `updated_at` > 90s → bloco esmaecido + "há Xm" (último-conhecido).
- **Settings:** edita `labels.json` (account_key → label, ordem, accent);
  "Iniciar no login" via `SMAppService`; intervalo de refresh.

### `labels.json` (gerido pelo app)

`~/Library/Application Support/tokenline/labels.json` — mapeia
`account_key → { label, order, accent }`. Editável pela UI de settings ou à mão.

## Layout do projeto

- Writer: mudança em `tokenline.sh` (repo existente, single source of truth).
- App: novo dir `widget/macos/` — projeto Xcode (`.xcodeproj`), target app macOS
  com `LSUIElement`. App separado como tooling, igual `src/` é o instalador npm.
- Protótipo SwiftBar (degrau de validação): plugin bash em `widget/swiftbar/`
  que lê o **mesmo** store/schema e cospe texto na barra. Valida o contrato JSON
  antes de escrever Swift; descartável.

## Tratamento de erro / hard constraints

- Writer opt-in, isolado, ShellCheck-clean, nunca exit≠0, nunca bloqueia render.
- Statusline byte-idêntica com e sem `TOKENLINE_WIDGET=1` (só efeito colateral: o
  arquivo). Nenhuma dependência nova obrigatória (jq/coreutils já são req).
- App tolera store vazio, contas sumindo, json corrompido, relógio torto.

## Testes

- **Bash:** alimentar payload de exemplo com `TOKENLINE_WIDGET=1
  TOKENLINE_WIDGET_DIR=<tmp>`; asserir (a) json escrito com campos certos, (b)
  throttle respeitado, (c) **output da statusline idêntico** com/sem a flag, (d)
  ShellCheck limpo. Roda no CI junto do shellcheck existente.
- **Swift:** unit test do `Codable` do snapshot, da seleção "pior conta" e da
  lógica de staleness. UI manual.

## Escopo / YAGNI (cortes do v1)

- Sem custo em **$** (só tokens).
- Sem histórico/sparkline persistido (layout é B denso, não o spark).
- Sem notificações (alerta quando conta >90%) — anotado como futuro.
- Sem Linux/Windows no app (menu bar é macOS). O **writer** é cross-platform e
  fica disponível de graça para futuros leitores.

## Futuro (não-v1)

- Notificação ao cruzar limiar de 5h/7d.
- Custo em $ para contas API-key (tabela de preço por modelo).
- "Gasto hoje" / histórico diário (exige histórico persistido por conta).
- WidgetKit de desktop como leitor alternativo do mesmo store.

## Questões em aberto

- Nome/bundle id do app (`tech.inbrace.tokenline.widget`?).
- Distribuição: build local via Xcode no v1; notarização/Homebrew cask depois.
