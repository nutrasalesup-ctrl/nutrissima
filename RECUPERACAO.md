# Nutríssima — Guia de Recuperação do Sistema

> Leia isto quando algo der errado: app fora do ar, banco pausado, dado apagado
> ou — pior caso — o projeto Supabase inteiro perdido.
> Escrito em 23/07/2026. Em dúvida, abra uma conversa no projeto Nutríssima do
> Claude e cole o problema: ele conhece este procedimento e executa os passos.
>
> ⚠️ Este repositório é **público**. Nenhuma senha, PIN ou chave secreta está
> aqui — e nada disso deve ser adicionado aqui jamais. Ver seção "Onde estão as
> senhas" no fim.

## O sistema em 3 camadas — e onde está a cópia de cada uma

| Camada | O que é | Onde vive | Cópia de segurança |
|---|---|---|---|
| **Telas (app)** | `index.html` | GitHub Pages (este repositório) | Histórico de commits do GitHub — toda versão antiga é recuperável |
| **Motor (schema)** | Tabelas, funções (RPCs), regras de segurança | Dentro do banco Supabase | **`db/schema.sql`** neste repositório — reconstrói o motor do zero |
| **Dados** | Estoques, receitas, programação, pedidos, movimentos | Banco Supabase (projeto `nfzospymzvlwzlcpgolm`) | Snapshot diário automático (6h UTC, retenção 7 dias) no schema `backup` — **dentro do mesmo projeto** |

---

## Cenário 1 — O app quebrou depois de uma atualização

Sintoma: o site https://nutrasalesup-ctrl.github.io/nutrissima/ abre em branco,
com erro, ou uma tela sumiu.

1. Entre em https://github.com/nutrasalesup-ctrl/nutrissima/commits/main
2. Ache o último commit **anterior** ao problema (pela data/hora).
3. Clique no commit → clique no arquivo `index.html` → botão `...` → **View file**
   → botão `...` de novo → **Download** (ou copie o conteúdo bruto em Raw).
4. Volte à página principal do repositório, abra `index.html`, clique no lápis
   (editar), cole o conteúdo antigo por cima e faça commit.
5. Espere 1–2 minutos (o GitHub Pages republica sozinho) e teste o link oficial.

Atalho: pedir ao Claude "o app quebrou, restaura a versão anterior" — ele faz
isso pela API validando o JavaScript antes de publicar.

## Cenário 2 — Banco "pausado" (plano free do Supabase)

Sintoma: o app abre mas nada carrega / erro de conexão. O plano free pausa o
projeto após ~1 semana sem uso. **Nenhum dado é perdido.**

1. Entre em https://supabase.com com a conta Google da fábrica.
2. Abra o projeto **nutrissima-producao**.
3. Clique em **Restore project** e aguarde alguns minutos.
4. Recarregue o app — volta tudo ao normal, sem reconfigurar nada.

## Cenário 3 — Lançamento errado ou dados apagados por engano

O banco tira uma foto de tudo todo dia às 6h UTC (3h da manhã em Brasília),
guardada por 7 dias no schema `backup` (ex.: `backup.itens_20260722`).

- Para **corrigir um saldo**: usar a RPC `ajustar_estoque` (pela tela Estoque ou
  pedindo ao Claude) — ela exige motivo e deixa rastro auditável.
- Para **consultar como algo estava ontem**:
  `select * from backup.itens_20260722 where nome ilike '%açúcar%';`
- Para **restaurar linhas apagadas**, pedir ao Claude, que monta o
  `insert ... select` a partir do snapshot certo. Regra da casa: toda escrita em
  produção só acontece com o seu "pode" explícito.

⚠️ Limitação conhecida: o snapshot cobre 16 tabelas — `depara_sku`,
`demanda_vendas`, `despachos_ecommerce`, `tarefas`, `metas_dia` e
`quadro_recado` ficam de fora (pendência aberta). Dessas, só `depara_sku` dói
de verdade se perder (os de-para são reconstruíveis, mas dá trabalho).

## Cenário 4 — Perda total do projeto Supabase (pior caso)

Conta hackeada, projeto excluído, região fora do ar. Aqui o `db/schema.sql`
deste repositório é o que separa "algumas horas de trabalho" de "semanas".

1. **Criar projeto novo** em https://supabase.com — região `sa-east-1`,
   guardar a senha do banco.
2. **Rodar o motor**: abrir o SQL Editor do projeto novo, colar o conteúdo
   inteiro de `db/schema.sql` e executar. Isso recria tipos, 22 tabelas,
   19 funções, regras de segurança e o mecanismo de backup. (Testado: o
   arquivo roda limpo num banco vazio.)
3. **Habilitar o backup diário**: Dashboard → Database → Extensions → ativar
   `pg_cron`; depois, no SQL Editor:
   `select cron.schedule('backup-diario', '0 6 * * *', 'select backup.fn_snapshot()');`
4. **Recriar o login do app** — NUNCA por INSERT manual em `auth.users` (quebra
   a autenticação). Usar o endpoint `POST {url-do-projeto}/auth/v1/signup` com
   e-mail e senha da fábrica, e confirmar o e-mail via SQL
   (`update auth.users set email_confirmed_at = now() where email = '...';`).
   O Claude sabe fazer os dois passos.
5. **Recriar o PIN do Gestor** (o valor está no documento-mestre do projeto
   Claude, não aqui):
   `update operadores set pin_hash = crypt('PIN_AQUI', gen_salt('bf')) where nome = 'Gestor';`
6. **Apontar o app pro projeto novo**: pegar a URL e a chave *publishable*
   (`sb_publishable_...`) em Settings → API do projeto novo; editar as duas no
   `index.html` deste repositório (ou colar a chave na tela Configuração de
   cada aparelho, conforme o app pedir).
7. **Repovoar os dados** — a parte trabalhosa, porque os snapshots moravam
   dentro do projeto perdido:
   - Cadastros (itens, fornecedores, produtos, receitas, SKUs): reconstruir a
     partir do documento-mestre e dos arquivos de receitas do projeto Claude —
     as receitas decodificadas estão lá, não se perdem com o banco.
   - Saldos: inventário físico (contagem), lançado via `ajustar_estoque` — o
     mesmo ritual já feito em 16/07 e 20/07.
   - Programação da semana: relançar pela tela Programação.
8. **Avisar o Claude** pra atualizar o documento-mestre com o id do projeto
   novo.

## O que este backup NÃO cobre (seja honesto com o risco)

Os **dados do dia a dia** têm cópia apenas dentro do próprio Supabase. Se o
projeto inteiro sumir, schema e app se recuperam deste repositório, mas os
saldos voltam por contagem física. Dois upgrades possíveis quando fizer
sentido: export periódico dos dados pra fora do Supabase, e/ou o plano Pro
(backup gerenciado + sem pausa automática).

## Onde estão as senhas e chaves (referência — os VALORES não ficam aqui)

| Segredo | Onde está guardado |
|---|---|
| Login do app (e-mail/senha da fábrica) | Documento-mestre do projeto Claude |
| PIN do gestor | Documento-mestre do projeto Claude |
| Conta Supabase / Google da fábrica | Com o dono |
| Token de publicação do GitHub (`github_pat_...`) | Conversas do projeto Claude (expira ~out/2026 — recriar igual ao original: fine-grained, só este repo, Contents read/write) |
| Chave `sb_publishable_...` | Pode ficar no app (é pública por natureza); valor atual no documento-mestre |
| Chaves `sb_secret_...` | **Nunca** saem do painel do Supabase |

## Checklist pós-recuperação (teste de fumaça)

1. Login no app funciona e a tela Estoque carrega com números.
2. `select * from receita_validacao where not fecha_100;` → deve voltar vazio.
3. `select count(*) from fn_mrp();` → roda sem erro.
4. Uma entrada de teste na tela "Entrada no estoque" + baixa na tela "Produtos
   separados" → o saldo sobe e desce, e as duas aparecem no log do Painel.
5. PIN do gestor abre Metas da semana.
6. No dia seguinte, conferir no log de atividades a linha "Backup automático
   concluído".
