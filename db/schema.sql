-- ============================================================================
-- Nutríssima — SCHEMA COMPLETO do banco de produção (ERP da Fábrica)
-- Projeto Supabase: nutrissima-producao (nfzospymzvlwzlcpgolm, sa-east-1)
-- Extraído de produção em 23/07/2026.
--
-- Este arquivo reconstrói o "motor" inteiro do sistema num projeto Supabase
-- novo: tipos, tabelas, constraints, índices, views, as 19 funções (RPCs),
-- RLS/políticas e o mecanismo de backup diário. NÃO contém dados nem segredos
-- (o PIN do gestor fica hasheado na tabela operadores, não aqui).
--
-- Como usar numa recuperação: ver RECUPERACAO.md na raiz do repositório.
-- Regra de manutenção: toda mudança de schema/função em produção deve ser
-- refletida aqui (pedir ao Claude "atualiza o schema.sql do repositório").
-- Substitui o antigo db/funcoes.sql (12/07), que cobria só 9 funções.
-- ============================================================================

set check_function_bodies = off;

-- ----------------------------------------------------------------------------
-- 0) EXTENSÕES
-- Num projeto Supabase novo: pgcrypto e uuid-ossp podem ser criadas por SQL;
-- pg_cron precisa ser habilitada antes em Dashboard → Database → Extensions.
-- ----------------------------------------------------------------------------
create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";
-- create extension if not exists pg_cron;  -- habilitar pelo painel do Supabase

-- ----------------------------------------------------------------------------
-- 1) TIPOS (enums)
-- ----------------------------------------------------------------------------
CREATE TYPE public.componente_tipo AS ENUM ('insumo', 'produto');
CREATE TYPE public.compra_status AS ENUM ('pendente', 'aguardando_pagamento', 'liberado', 'recebido', 'cancelado');
CREATE TYPE public.cor_produto AS ENUM ('claro', 'escuro');
CREATE TYPE public.item_categoria AS ENUM ('materia_prima', 'embalagem', 'pote', 'tampa', 'rotulo', 'caixa', 'aroma', 'outros');
CREATE TYPE public.movimento_tipo AS ENUM ('entrada', 'saida');

-- ----------------------------------------------------------------------------
-- 2) TABELAS
-- ----------------------------------------------------------------------------
CREATE TABLE public.atividades (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tipo text NOT NULL,
  descricao text NOT NULL,
  lote text,
  responsavel text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.compras (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  item_id uuid NOT NULL,
  fornecedor_id uuid,
  fornecedor_nome text,
  quantidade_solicitada numeric NOT NULL,
  quantidade_recebida numeric,
  preco_unitario numeric,
  condicao_pagamento text,
  prazo_pagamento_dias numeric,
  status compra_status DEFAULT 'pendente'::compra_status NOT NULL,
  data_pedido date,
  data_pagamento date,
  data_prevista_entrega date,
  data_recebimento date,
  lote_fornecedor text,
  observacao text,
  comprovante_path text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.demanda_vendas (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  produto_acabado_id uuid NOT NULL,
  plataforma text,
  qtd_potes numeric DEFAULT 0 NOT NULL,
  data_despacho date,
  status text DEFAULT 'aberto'::text NOT NULL,
  origem text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_por text
);

CREATE TABLE public.depara_sku (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  codigo text NOT NULL,
  plataforma text,
  nome_anuncio text,
  produto_acabado_id uuid,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_por text
);

CREATE TABLE public.despachos_ecommerce (
  id integer DEFAULT 1 NOT NULL,
  conteudo text,
  atualizado_em timestamp with time zone DEFAULT now(),
  atualizado_por text
);

CREATE TABLE public.equipamentos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  capacidade_kg_dia numeric,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE public.estoque_balde (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  produto_id uuid NOT NULL,
  quantidade_kg numeric DEFAULT 0 NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.estoque_balde_movimentos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  produto_id uuid NOT NULL,
  tipo movimento_tipo NOT NULL,
  quantidade_kg numeric NOT NULL,
  lote text,
  responsavel text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.fornecedor_itens (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  fornecedor_id uuid NOT NULL,
  item_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.fornecedores (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.itens (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  categoria item_categoria DEFAULT 'materia_prima'::item_categoria NOT NULL,
  unidade text DEFAULT 'kg'::text NOT NULL,
  estoque_minimo numeric,
  saldo_atual numeric DEFAULT 0 NOT NULL,
  lead_time_dias numeric,
  necessidade_dias numeric,
  fornecedor_id uuid,
  ordem integer,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.metas_dia (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  data date NOT NULL,
  area text NOT NULL,
  ref_id uuid NOT NULL,
  ref_nome text NOT NULL,
  meta numeric NOT NULL,
  unidade text NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.operadores (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  pin_hash text
);

CREATE TABLE public.parametros (
  chave text NOT NULL,
  valor numeric NOT NULL
);

CREATE TABLE public.pesagem_lotes_mp (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  programacao_id uuid NOT NULL,
  item_id uuid NOT NULL,
  lotes text NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.produto_acabado (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  linha text,
  embalagem text,
  saldo_potes numeric DEFAULT 0 NOT NULL,
  peso_pote_kg numeric,
  produto_id uuid,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE public.produto_acabado_movimentos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  produto_acabado_id uuid NOT NULL,
  tipo movimento_tipo NOT NULL,
  quantidade numeric NOT NULL,
  lote text,
  responsavel text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.produtos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  vendavel boolean DEFAULT true NOT NULL,
  estocavel_balde boolean DEFAULT false NOT NULL,
  cor cor_produto,
  lote_minimo_kg numeric,
  ativo boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.programacao_refino (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  produto_id uuid NOT NULL,
  equipamento_id uuid,
  data date NOT NULL,
  quantidade_kg numeric NOT NULL,
  status text DEFAULT 'programado'::text NOT NULL,
  lote text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  entrada_confirmada boolean DEFAULT false NOT NULL
);

CREATE TABLE public.quadro_recado (
  data date NOT NULL,
  recado text
);

CREATE TABLE public.receita_itens (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  produto_id uuid NOT NULL,
  componente_tipo componente_tipo NOT NULL,
  componente_insumo_id uuid,
  componente_produto_id uuid,
  qtd_por_100kg numeric NOT NULL
);

CREATE TABLE public.tarefas (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  data date NOT NULL,
  descricao text NOT NULL,
  responsavel_designado text,
  concluido boolean DEFAULT false NOT NULL,
  concluido_por text,
  concluido_em timestamp with time zone,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

-- ----------------------------------------------------------------------------
-- 3) CONSTRAINTS — chaves primárias, únicas, checks e estrangeiras
-- ----------------------------------------------------------------------------
ALTER TABLE public.atividades ADD CONSTRAINT atividades_pkey PRIMARY KEY (id);
ALTER TABLE public.compras ADD CONSTRAINT compras_pkey PRIMARY KEY (id);
ALTER TABLE public.demanda_vendas ADD CONSTRAINT demanda_vendas_pkey PRIMARY KEY (id);
ALTER TABLE public.depara_sku ADD CONSTRAINT depara_sku_pkey PRIMARY KEY (id);
ALTER TABLE public.despachos_ecommerce ADD CONSTRAINT despachos_ecommerce_pkey PRIMARY KEY (id);
ALTER TABLE public.equipamentos ADD CONSTRAINT equipamentos_pkey PRIMARY KEY (id);
ALTER TABLE public.estoque_balde ADD CONSTRAINT estoque_balde_pkey PRIMARY KEY (id);
ALTER TABLE public.estoque_balde_movimentos ADD CONSTRAINT estoque_balde_movimentos_pkey PRIMARY KEY (id);
ALTER TABLE public.fornecedor_itens ADD CONSTRAINT fornecedor_itens_pkey PRIMARY KEY (id);
ALTER TABLE public.fornecedores ADD CONSTRAINT fornecedores_pkey PRIMARY KEY (id);
ALTER TABLE public.itens ADD CONSTRAINT itens_pkey PRIMARY KEY (id);
ALTER TABLE public.metas_dia ADD CONSTRAINT metas_dia_pkey PRIMARY KEY (id);
ALTER TABLE public.operadores ADD CONSTRAINT operadores_pkey PRIMARY KEY (id);
ALTER TABLE public.parametros ADD CONSTRAINT parametros_pkey PRIMARY KEY (chave);
ALTER TABLE public.pesagem_lotes_mp ADD CONSTRAINT pesagem_lotes_mp_pkey PRIMARY KEY (id);
ALTER TABLE public.produto_acabado ADD CONSTRAINT produto_acabado_pkey PRIMARY KEY (id);
ALTER TABLE public.produto_acabado_movimentos ADD CONSTRAINT produto_acabado_movimentos_pkey PRIMARY KEY (id);
ALTER TABLE public.produtos ADD CONSTRAINT produtos_pkey PRIMARY KEY (id);
ALTER TABLE public.programacao_refino ADD CONSTRAINT programacao_refino_pkey PRIMARY KEY (id);
ALTER TABLE public.quadro_recado ADD CONSTRAINT quadro_recado_pkey PRIMARY KEY (data);
ALTER TABLE public.receita_itens ADD CONSTRAINT receita_itens_pkey PRIMARY KEY (id);
ALTER TABLE public.tarefas ADD CONSTRAINT tarefas_pkey PRIMARY KEY (id);

ALTER TABLE public.estoque_balde ADD CONSTRAINT estoque_balde_produto_id_key UNIQUE (produto_id);
ALTER TABLE public.fornecedor_itens ADD CONSTRAINT fornecedor_itens_fornecedor_id_item_id_key UNIQUE (fornecedor_id, item_id);
ALTER TABLE public.fornecedores ADD CONSTRAINT fornecedores_nome_key UNIQUE (nome);
ALTER TABLE public.itens ADD CONSTRAINT itens_nome_key UNIQUE (nome);
ALTER TABLE public.metas_dia ADD CONSTRAINT metas_dia_data_area_ref_id_key UNIQUE (data, area, ref_id);
ALTER TABLE public.operadores ADD CONSTRAINT operadores_nome_key UNIQUE (nome);
ALTER TABLE public.produto_acabado ADD CONSTRAINT produto_acabado_nome_linha_key UNIQUE (nome, linha);
ALTER TABLE public.produtos ADD CONSTRAINT produtos_nome_key UNIQUE (nome);

ALTER TABLE public.despachos_ecommerce ADD CONSTRAINT singleton CHECK ((id = 1));
ALTER TABLE public.metas_dia ADD CONSTRAINT metas_dia_area_check CHECK ((area = ANY (ARRAY['pesagem'::text, 'refino'::text, 'envase'::text])));
ALTER TABLE public.receita_itens ADD CONSTRAINT chk_componente CHECK ((((componente_tipo = 'insumo'::componente_tipo) AND (componente_insumo_id IS NOT NULL) AND (componente_produto_id IS NULL)) OR ((componente_tipo = 'produto'::componente_tipo) AND (componente_produto_id IS NOT NULL) AND (componente_insumo_id IS NULL))));

ALTER TABLE public.compras ADD CONSTRAINT compras_fornecedor_id_fkey FOREIGN KEY (fornecedor_id) REFERENCES fornecedores(id);
ALTER TABLE public.compras ADD CONSTRAINT compras_item_id_fkey FOREIGN KEY (item_id) REFERENCES itens(id);
ALTER TABLE public.demanda_vendas ADD CONSTRAINT demanda_vendas_produto_acabado_id_fkey FOREIGN KEY (produto_acabado_id) REFERENCES produto_acabado(id) ON DELETE CASCADE;
ALTER TABLE public.depara_sku ADD CONSTRAINT depara_sku_produto_acabado_id_fkey FOREIGN KEY (produto_acabado_id) REFERENCES produto_acabado(id) ON DELETE SET NULL;
ALTER TABLE public.estoque_balde ADD CONSTRAINT estoque_balde_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES produtos(id);
ALTER TABLE public.estoque_balde_movimentos ADD CONSTRAINT estoque_balde_movimentos_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES produtos(id);
ALTER TABLE public.fornecedor_itens ADD CONSTRAINT fornecedor_itens_fornecedor_id_fkey FOREIGN KEY (fornecedor_id) REFERENCES fornecedores(id) ON DELETE CASCADE;
ALTER TABLE public.fornecedor_itens ADD CONSTRAINT fornecedor_itens_item_id_fkey FOREIGN KEY (item_id) REFERENCES itens(id) ON DELETE CASCADE;
ALTER TABLE public.itens ADD CONSTRAINT itens_fornecedor_id_fkey FOREIGN KEY (fornecedor_id) REFERENCES fornecedores(id);
ALTER TABLE public.pesagem_lotes_mp ADD CONSTRAINT pesagem_lotes_mp_item_id_fkey FOREIGN KEY (item_id) REFERENCES itens(id);
ALTER TABLE public.pesagem_lotes_mp ADD CONSTRAINT pesagem_lotes_mp_programacao_id_fkey FOREIGN KEY (programacao_id) REFERENCES programacao_refino(id) ON DELETE CASCADE;
ALTER TABLE public.produto_acabado ADD CONSTRAINT produto_acabado_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES produtos(id);
ALTER TABLE public.produto_acabado_movimentos ADD CONSTRAINT produto_acabado_movimentos_produto_acabado_id_fkey FOREIGN KEY (produto_acabado_id) REFERENCES produto_acabado(id);
ALTER TABLE public.programacao_refino ADD CONSTRAINT programacao_refino_equipamento_id_fkey FOREIGN KEY (equipamento_id) REFERENCES equipamentos(id);
ALTER TABLE public.programacao_refino ADD CONSTRAINT programacao_refino_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES produtos(id);
ALTER TABLE public.receita_itens ADD CONSTRAINT receita_itens_componente_insumo_id_fkey FOREIGN KEY (componente_insumo_id) REFERENCES itens(id);
ALTER TABLE public.receita_itens ADD CONSTRAINT receita_itens_componente_produto_id_fkey FOREIGN KEY (componente_produto_id) REFERENCES produtos(id);
ALTER TABLE public.receita_itens ADD CONSTRAINT receita_itens_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES produtos(id) ON DELETE CASCADE;

-- ----------------------------------------------------------------------------
-- 4) ÍNDICES (além dos criados pelas constraints)
-- ----------------------------------------------------------------------------
CREATE INDEX demanda_vendas_pa_idx ON public.demanda_vendas USING btree (produto_acabado_id);
CREATE INDEX demanda_vendas_status_idx ON public.demanda_vendas USING btree (status);
CREATE UNIQUE INDEX depara_sku_codigo_uk ON public.depara_sku USING btree (codigo);
CREATE INDEX idx_tarefas_data ON public.tarefas USING btree (data);

-- ----------------------------------------------------------------------------
-- 5) VIEWS
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.receita_validacao AS
 SELECT p.id,
    p.nome,
    round(sum(ri.qtd_por_100kg), 2) AS soma,
    (abs((sum(ri.qtd_por_100kg) - (100)::numeric)) <= 0.05) AS fecha_100
   FROM (produtos p
     JOIN receita_itens ri ON ((ri.produto_id = p.id)))
  GROUP BY p.id, p.nome;

-- ----------------------------------------------------------------------------
-- 6) FUNÇÕES (RPCs) — o motor do sistema. fn_explode primeiro (as outras dependem).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_explode(p_produto uuid, p_kg numeric)
 RETURNS TABLE(item_id uuid, kg numeric, balde_produto_id uuid, balde_kg numeric)
 LANGUAGE plpgsql
AS $function$
begin
  return query
  with recursive arvore as (
    select ri.componente_tipo, ri.componente_insumo_id, ri.componente_produto_id,
           (p_kg * ri.qtd_por_100kg / 100)::numeric as kg
    from receita_itens ri where ri.produto_id = p_produto
    union all
    select ri.componente_tipo, ri.componente_insumo_id, ri.componente_produto_id,
           (a.kg * ri.qtd_por_100kg / 100)::numeric
    from arvore a
    join produtos pr on pr.id = a.componente_produto_id and pr.estocavel_balde = false
    join receita_itens ri on ri.produto_id = pr.id
    where a.componente_tipo = 'produto'
  )
  select a.componente_insumo_id, sum(a.kg), null::uuid, null::numeric
    from arvore a where a.componente_tipo = 'insumo' group by 1
  union all
  select null::uuid, null::numeric, a.componente_produto_id, sum(a.kg)
    from arvore a
    join produtos pr on pr.id = a.componente_produto_id and pr.estocavel_balde = true
    where a.componente_tipo = 'produto' group by 3;
end $function$
;

CREATE OR REPLACE FUNCTION public.ajustar_estoque(p_tipo text, p_id uuid, p_saldo_real numeric, p_motivo text, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_atual numeric; v_nome text; v_un text; v_diff numeric;
begin
  if p_saldo_real is null or p_saldo_real < 0 then raise exception 'Saldo real inválido'; end if;
  if coalesce(trim(p_motivo),'') = '' then raise exception 'Informe o motivo do ajuste'; end if;

  if p_tipo = 'item' then
    select saldo_atual, nome, unidade into v_atual, v_nome, v_un from itens where id = p_id for update;
    if v_nome is null then raise exception 'Item não encontrado'; end if;
    update itens set saldo_atual = p_saldo_real, updated_at = now() where id = p_id;

  elsif p_tipo = 'balde' then
    select eb.quantidade_kg, p.nome, 'kg' into v_atual, v_nome, v_un
      from estoque_balde eb join produtos p on p.id = eb.produto_id where eb.produto_id = p_id for update;
    if v_nome is null then raise exception 'Balde não encontrado'; end if;
    update estoque_balde set quantidade_kg = p_saldo_real, atualizado_em = now() where produto_id = p_id;
    v_diff := p_saldo_real - v_atual;
    if v_diff <> 0 then
      insert into estoque_balde_movimentos(produto_id, tipo, quantidade_kg, lote, responsavel)
      values (p_id, (case when v_diff > 0 then 'entrada' else 'saida' end)::movimento_tipo, abs(v_diff), 'AJUSTE', p_responsavel);
    end if;

  elsif p_tipo = 'pa' then
    select saldo_potes, nome, 'potes' into v_atual, v_nome, v_un from produto_acabado where id = p_id for update;
    if v_nome is null then raise exception 'Produto acabado não encontrado'; end if;
    update produto_acabado set saldo_potes = p_saldo_real where id = p_id;
    v_diff := p_saldo_real - v_atual;
    if v_diff <> 0 then
      insert into produto_acabado_movimentos(produto_acabado_id, tipo, quantidade, lote, responsavel)
      values (p_id, (case when v_diff > 0 then 'entrada' else 'saida' end)::movimento_tipo, abs(v_diff), 'AJUSTE', p_responsavel);
    end if;

  else
    raise exception 'Tipo de ajuste desconhecido: %', p_tipo;
  end if;

  insert into atividades(tipo, descricao, lote, responsavel)
  values ('ajuste', format('Ajuste — %s: %s → %s %s (%s)', v_nome, round(v_atual,2), round(p_saldo_real,2), v_un, p_motivo), null, p_responsavel);
end $function$
;

CREATE OR REPLACE FUNCTION public.baixa_balde(p_produto_id uuid, p_kg numeric, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_nome text; v_saldo numeric;
begin
  if p_kg is null or p_kg<=0 then raise exception 'Quantidade inválida'; end if;
  select p.nome, eb.quantidade_kg into v_nome, v_saldo from produtos p left join estoque_balde eb on eb.produto_id=p.id where p.id=p_produto_id;
  if v_nome is null then raise exception 'Produto não encontrado'; end if;
  update estoque_balde set quantidade_kg = greatest(0, quantidade_kg - p_kg), atualizado_em=now() where produto_id=p_produto_id;
  insert into estoque_balde_movimentos(produto_id,tipo,quantidade_kg,lote,responsavel) values (p_produto_id,'saida'::movimento_tipo,p_kg,'MANUAL',p_responsavel);
  insert into atividades(tipo,descricao,responsavel) values ('balde', format('Baixa de balde — %s: -%s kg', v_nome, round(p_kg,1)), p_responsavel);
end $function$
;

CREATE OR REPLACE FUNCTION public.baixa_balde_mix(p_produto_mix uuid, p_kg_total numeric, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_nome_mix text; v_desc text := ''; r record; v_kg numeric;
begin
  if p_kg_total is null or p_kg_total<=0 then raise exception 'Quantidade inválida'; end if;
  select nome into v_nome_mix from produtos where id=p_produto_mix;
  if v_nome_mix is null then raise exception 'Produto (mistura) não encontrado'; end if;

  for r in
    select ri.componente_produto_id, ri.qtd_por_100kg, p.nome as nome_componente
    from receita_itens ri join produtos p on p.id=ri.componente_produto_id
    where ri.produto_id=p_produto_mix and ri.componente_tipo='produto' and p.estocavel_balde=true
  loop
    v_kg := round(p_kg_total * r.qtd_por_100kg/100.0, 3);
    update estoque_balde set quantidade_kg = greatest(0, quantidade_kg - v_kg), atualizado_em=now() where produto_id=r.componente_produto_id;
    insert into estoque_balde_movimentos(produto_id,tipo,quantidade_kg,lote,responsavel)
      values (r.componente_produto_id,'saida'::movimento_tipo,v_kg,'MANUAL-MIX',p_responsavel);
    v_desc := v_desc || format('%s: -%s kg; ', r.nome_componente, v_kg);
  end loop;

  if v_desc = '' then raise exception 'Esse produto não tem receita de mistura cadastrada com componentes em balde'; end if;

  insert into atividades(tipo,descricao,responsavel)
    values ('balde', format('Baixa de balde (mistura %s, %s kg total) — %s', v_nome_mix, round(p_kg_total,1), v_desc), p_responsavel);
end $function$
;

CREATE OR REPLACE FUNCTION public.baixa_despacho(p_pa uuid, p_potes numeric, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_saldo numeric; v_nome text;
begin
  if p_potes is null or p_potes<=0 then raise exception 'Quantidade inválida'; end if;
  select saldo_potes, nome into v_saldo, v_nome from produto_acabado where id=p_pa for update;
  if v_nome is null then raise exception 'Produto não encontrado'; end if;
  update produto_acabado set saldo_potes = greatest(0, saldo_potes - p_potes) where id=p_pa;
  insert into produto_acabado_movimentos(produto_acabado_id, tipo, quantidade, lote, responsavel)
  values (p_pa, 'saida'::movimento_tipo, p_potes, 'DESPACHO', p_responsavel);
  insert into atividades(tipo, descricao, responsavel)
  values ('despacho', format('Produtos separados — %s: -%s potes', v_nome, round(p_potes,2)), p_responsavel);
end $function$
;

CREATE OR REPLACE FUNCTION public.baixa_item(p_item uuid, p_qtd numeric, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_nome text; v_un text;
begin
  if p_qtd is null or p_qtd<=0 then raise exception 'Quantidade inválida'; end if;
  select nome, unidade into v_nome, v_un from itens where id=p_item;
  if v_nome is null then raise exception 'Item não encontrado'; end if;
  update itens set saldo_atual = greatest(0, saldo_atual - p_qtd), updated_at=now() where id=p_item;
  insert into atividades(tipo,descricao,responsavel) values ('item', format('Baixa de matéria-prima — %s: -%s %s', v_nome, round(p_qtd,2), coalesce(v_un,'')), p_responsavel);
end $function$
;

CREATE OR REPLACE FUNCTION public.concluir_refino(p_prog uuid, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_prod uuid; v_lote text; v_nome text;
begin
  select pr.produto_id, pr.lote, p.nome into v_prod, v_lote, v_nome
  from programacao_refino pr join produtos p on p.id=pr.produto_id where pr.id=p_prog and pr.status='refino' for update;
  if v_prod is null then raise exception 'Programação não encontrada ou não está em status refino'; end if;
  update programacao_refino set status='balde' where id=p_prog;
  insert into atividades(tipo,descricao,lote,responsavel) values ('balde', format('Batelada concluída — %s (lance a entrada no balde em Entrada de balde)', v_nome), v_lote, p_responsavel);
end
$function$
;

CREATE OR REPLACE FUNCTION public.confirmar_pesagem(p_prog uuid, p_responsavel text, p_lote text, p_lotes jsonb DEFAULT '[]'::jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
declare v_prod uuid; v_kg numeric; v_perda numeric; v_pesar numeric; v_nome text; r record; l record;
begin
  select produto_id, quantidade_kg into v_prod, v_kg from programacao_refino where id=p_prog and status='programado' for update;
  if v_prod is null then raise exception 'Programação não encontrada ou já pesada'; end if;
  select valor into v_perda from parametros where chave='perda_processo_pct';
  v_pesar := v_kg / (1 - coalesce(v_perda,3)/100.0);
  for r in select * from fn_explode(v_prod, v_pesar) loop
    if r.item_id is not null then
      update itens set saldo_atual = saldo_atual - r.kg, updated_at=now() where id = r.item_id;
    else
      update estoque_balde set quantidade_kg = quantidade_kg - r.balde_kg, atualizado_em=now() where produto_id = r.balde_produto_id;
      insert into estoque_balde_movimentos(produto_id,tipo,quantidade_kg,lote,responsavel) values (r.balde_produto_id,'saida',r.balde_kg,p_lote,p_responsavel);
    end if;
  end loop;
  -- registra os lotes de MP informados
  for l in select (e->>'item_id')::uuid as item_id, e->>'lotes' as lotes
           from jsonb_array_elements(coalesce(p_lotes,'[]')) e
           where coalesce(trim(e->>'lotes'),'') <> '' loop
    insert into pesagem_lotes_mp(programacao_id, item_id, lotes) values (p_prog, l.item_id, l.lotes);
  end loop;
  update programacao_refino set status='pesado', lote=p_lote where id=p_prog;
  select nome into v_nome from produtos where id=v_prod;
  insert into atividades(tipo,descricao,lote,responsavel) values ('pesagem', format('Pesagem — %s, %s kg (c/ perda: %s kg pesados)', v_nome, round(v_kg,1), round(v_pesar,1)), p_lote, p_responsavel);
  return p_lote;
end $function$
;

CREATE OR REPLACE FUNCTION public.confirmar_recebimento(p_compra uuid, p_qtd numeric, p_lote text, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_item uuid; v_nome text; v_un text;
begin
  select item_id into v_item from compras where id=p_compra and status='liberado' for update;
  if v_item is null then raise exception 'Compra não encontrada ou não está liberada'; end if;
  update itens set saldo_atual = saldo_atual + p_qtd, updated_at=now() where id=v_item returning nome, unidade into v_nome, v_un;
  update compras set status='recebido', quantidade_recebida=p_qtd, data_recebimento=current_date, lote_fornecedor=p_lote, updated_at=now() where id=p_compra;
  insert into atividades(tipo,descricao,lote,responsavel) values ('recebimento', format('Recebimento — %s %s de %s', p_qtd, v_un, v_nome), p_lote, p_responsavel);
end $function$
;

CREATE OR REPLACE FUNCTION public.confirmar_recebimento_parcial(p_compra uuid, p_qtd numeric, p_lote text, p_responsavel text, p_data_saldo date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
declare
  v compras%rowtype;
  v_nome text; v_un text; v_saldo numeric; v_novo uuid;
begin
  select * into v from compras where id = p_compra and status = 'liberado' for update;
  if v.id is null then raise exception 'Compra não encontrada ou não está liberada'; end if;
  if p_qtd is null or p_qtd <= 0 then raise exception 'Quantidade inválida'; end if;

  v_saldo := v.quantidade_solicitada - p_qtd;
  if v_saldo <= 0 then
    raise exception 'Não é entrega parcial (chegou % de %). Use confirmar_recebimento.', p_qtd, v.quantidade_solicitada;
  end if;

  -- 1) entrada do que chegou
  update itens set saldo_atual = saldo_atual + p_qtd, updated_at = now()
  where id = v.item_id returning nome, unidade into v_nome, v_un;

  -- 2) fecha o pedido original preservando o que foi pedido x o que chegou
  update compras set
    status = 'recebido',
    quantidade_recebida = p_qtd,
    data_recebimento = current_date,
    lote_fornecedor = p_lote,
    observacao = coalesce(observacao || ' | ', '') ||
      format('Entrega parcial: chegou %s de %s %s; saldo de %s %s reprogramado', p_qtd, v.quantidade_solicitada, v_un, v_saldo, v_un),
    updated_at = now()
  where id = p_compra;

  -- 3) pedido-filho com o saldo que o fornecedor ainda deve
  insert into compras (item_id, fornecedor_id, fornecedor_nome, quantidade_solicitada,
                       preco_unitario, condicao_pagamento, prazo_pagamento_dias,
                       status, data_pedido, data_prevista_entrega, observacao)
  values (v.item_id, v.fornecedor_id, v.fornecedor_nome, v_saldo,
          v.preco_unitario, v.condicao_pagamento, v.prazo_pagamento_dias,
          'liberado', v.data_pedido, p_data_saldo,
          format('Saldo do pedido de %s (chegou %s de %s %s em %s)',
                 coalesce(to_char(v.data_pedido, 'DD/MM/YYYY'), '—'), p_qtd, v.quantidade_solicitada, v_un,
                 to_char(current_date, 'DD/MM/YYYY')))
  returning id into v_novo;

  insert into atividades (tipo, descricao, lote, responsavel)
  values ('recebimento',
          format('Recebimento parcial — %s %s de %s (saldo de %s %s previsto p/ %s)',
                 p_qtd, v_un, v_nome, v_saldo, v_un, coalesce(to_char(p_data_saldo, 'DD/MM/YYYY'), 'sem data')),
          p_lote, p_responsavel);

  return v_novo;
end
$function$
;

CREATE OR REPLACE FUNCTION public.entrada_balde(p_produto_id uuid, p_kg numeric, p_responsavel text, p_lote text DEFAULT 'MANUAL'::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_nome text;
begin
  if p_kg is null or p_kg<=0 then raise exception 'Quantidade inválida'; end if;
  select nome into v_nome from produtos where id=p_produto_id;
  if v_nome is null then raise exception 'Produto não encontrado'; end if;
  insert into estoque_balde(produto_id,quantidade_kg) values (p_produto_id,p_kg)
    on conflict (produto_id) do update set quantidade_kg = estoque_balde.quantidade_kg + p_kg, atualizado_em=now();
  insert into estoque_balde_movimentos(produto_id,tipo,quantidade_kg,lote,responsavel) values (p_produto_id,'entrada'::movimento_tipo,p_kg,coalesce(nullif(trim(p_lote),''),'MANUAL'),p_responsavel);
  insert into atividades(tipo,descricao,responsavel) values ('balde', format('Entrada de balde — %s: +%s kg', v_nome, round(p_kg,1)), p_responsavel);
end
$function$
;

CREATE OR REPLACE FUNCTION public.entrada_item(p_item uuid, p_qtd numeric, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_nome text; v_un text;
begin
  if p_qtd is null or p_qtd<=0 then raise exception 'Quantidade inválida'; end if;
  select nome, unidade into v_nome, v_un from itens where id=p_item;
  if v_nome is null then raise exception 'Item não encontrado'; end if;
  update itens set saldo_atual = saldo_atual + p_qtd, updated_at=now() where id=p_item;
  insert into atividades(tipo,descricao,responsavel) values ('item', format('Entrada de matéria-prima — %s: +%s %s', v_nome, round(p_qtd,2), coalesce(v_un,'')), p_responsavel);
end $function$
;

CREATE OR REPLACE FUNCTION public.entrada_potes(p_pa uuid, p_potes numeric, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_nome text;
begin
  if p_potes is null or p_potes<=0 then raise exception 'Quantidade inválida'; end if;
  select nome into v_nome from produto_acabado where id=p_pa;
  if v_nome is null then raise exception 'Produto não encontrado'; end if;
  update produto_acabado set saldo_potes = saldo_potes + p_potes where id=p_pa;
  insert into produto_acabado_movimentos(produto_acabado_id,tipo,quantidade,lote,responsavel) values (p_pa,'entrada'::movimento_tipo,p_potes,'MANUAL',p_responsavel);
  insert into atividades(tipo,descricao,responsavel) values ('envase', format('Entrada no estoque — %s: +%s potes', v_nome, round(p_potes,0)), p_responsavel);
end $function$
;

CREATE OR REPLACE FUNCTION public.envasar(p_produto uuid, p_pa uuid, p_potes integer, p_responsavel text, p_lote text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
  v_peso numeric; v_nome_pa text; v_prod_pa uuid; v_kg numeric;
  v_saldo numeric; v_nome_prod text; v_multi boolean; r record; v_detalhe text := '';
begin
  select peso_pote_kg, nome, produto_id into v_peso, v_nome_pa, v_prod_pa
  from produto_acabado where id = p_pa for update;
  if v_peso is null then raise exception 'Cadastre o peso do pote deste produto antes de envasar'; end if;
  v_kg := p_potes * v_peso;

  v_multi := v_prod_pa is not null and exists (select 1 from receita_itens where produto_id = v_prod_pa);

  if v_multi then
    -- Explosão completa da receita: valida todos os baldes antes de debitar qualquer coisa
    for r in select * from fn_explode(v_prod_pa, v_kg) loop
      if r.balde_produto_id is not null then
        select quantidade_kg into v_saldo from estoque_balde where produto_id = r.balde_produto_id for update;
        select nome into v_nome_prod from produtos where id = r.balde_produto_id;
        if v_saldo is null or v_saldo < r.balde_kg then
          raise exception 'Saldo insuficiente no balde de % (tem % kg, precisa % kg)', v_nome_prod, coalesce(round(v_saldo,1),0), round(r.balde_kg,2);
        end if;
      end if;
    end loop;
    for r in select * from fn_explode(v_prod_pa, v_kg) loop
      if r.balde_produto_id is not null then
        update estoque_balde set quantidade_kg = quantidade_kg - r.balde_kg, atualizado_em = now() where produto_id = r.balde_produto_id;
        insert into estoque_balde_movimentos(produto_id, tipo, quantidade_kg, lote, responsavel)
        values (r.balde_produto_id, 'saida', r.balde_kg, p_lote, p_responsavel);
        select nome into v_nome_prod from produtos where id = r.balde_produto_id;
        v_detalhe := v_detalhe || v_nome_prod || ' ' || round(r.balde_kg,1) || 'kg + ';
      else
        update itens set saldo_atual = saldo_atual - r.kg, updated_at = now() where id = r.item_id;
      end if;
    end loop;
    v_detalhe := rtrim(v_detalhe, ' +');
    insert into atividades(tipo, descricao, lote, responsavel)
    values ('envase', format('Envase — %s potes de %s (receita: %s + insumos)', p_potes, v_nome_pa, v_detalhe), p_lote, p_responsavel);
  else
    if p_produto is null then raise exception 'Escolha o balde de origem'; end if;
    select quantidade_kg into v_saldo from estoque_balde where produto_id = p_produto for update;
    if v_saldo is null or v_saldo < v_kg then
      raise exception 'Saldo insuficiente no balde (% kg, precisa % kg)', coalesce(round(v_saldo,1),0), round(v_kg,1);
    end if;
    update estoque_balde set quantidade_kg = quantidade_kg - v_kg, atualizado_em = now() where produto_id = p_produto;
    insert into estoque_balde_movimentos(produto_id, tipo, quantidade_kg, lote, responsavel)
    values (p_produto, 'saida', v_kg, p_lote, p_responsavel);
    select nome into v_nome_prod from produtos where id = p_produto;
    insert into atividades(tipo, descricao, lote, responsavel)
    values ('envase', format('Envase — %s potes de %s (%s kg do balde %s)', p_potes, v_nome_pa, round(v_kg,1), v_nome_prod), p_lote, p_responsavel);
  end if;

  update produto_acabado set saldo_potes = saldo_potes + p_potes where id = p_pa;
  insert into produto_acabado_movimentos(produto_acabado_id, tipo, quantidade, lote, responsavel)
  values (p_pa, 'entrada', p_potes, p_lote, p_responsavel);
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_alerta_entregas()
 RETURNS TABLE(item_id uuid, item text, unidade text, data_producao date, necessario_ate numeric, disponivel_ate numeric, falta numeric, proxima_entrega date)
 LANGUAGE sql
 STABLE
AS $function$
with perda as (
  select coalesce((select valor from parametros where chave='perda_processo_pct'),3)/100.0 as p
),
necessidade as (
  select e.item_id, pr.data, sum(e.kg/(1-(select p from perda))) as kg
  from programacao_refino pr
  cross join lateral fn_explode(pr.produto_id, pr.quantidade_kg) e
  where pr.status='programado' and e.item_id is not null
  group by e.item_id, pr.data
),
acum as (
  select item_id, data,
         sum(kg) over (partition by item_id order by data) as necessario_ate
  from necessidade
),
calc as (
  select a.item_id, a.data, a.necessario_ate,
    coalesce((select sum(c.quantidade_solicitada) from compras c
      where c.item_id=a.item_id
        and c.status in ('pendente','aguardando_pagamento','liberado')
        and c.data_prevista_entrega is not null
        and c.data_prevista_entrega <= a.data),0) as chega_ate,
    (select min(c.data_prevista_entrega) from compras c
      where c.item_id=a.item_id
        and c.status in ('pendente','aguardando_pagamento','liberado')
        and c.data_prevista_entrega > a.data) as proxima_entrega
  from acum a
)
select c.item_id, i.nome, i.unidade, c.data,
       round(c.necessario_ate,1),
       round(i.saldo_atual + c.chega_ate,1),
       round(c.necessario_ate - (i.saldo_atual + c.chega_ate),1),
       c.proxima_entrega
from calc c
join itens i on i.id = c.item_id
where c.necessario_ate > i.saldo_atual + c.chega_ate + 0.01
order by c.data, 7 desc;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_mrp()
 RETURNS TABLE(item_id uuid, nome text, unidade text, necessidade numeric, saldo numeric, estoque_minimo numeric, a_caminho numeric, a_comprar numeric, lead_time_dias numeric, data_producao date, pedir_ate date, status text)
 LANGUAGE plpgsql
AS $function$
declare v_perda numeric; v_margem numeric;
begin
  select valor into v_perda from parametros where chave='perda_processo_pct';
  select valor into v_margem from parametros where chave='margem_seguranca_dias';
  return query
  with pend as (
    select pr.produto_id, pr.data, pr.quantidade_kg / (1 - coalesce(v_perda,3)/100.0) as kg_pesar
    from programacao_refino pr where pr.status = 'programado'
  ),
  detalhe as (
    select p.data as dt, e.item_id as iid, e.kg as kg
    from pend p cross join lateral fn_explode(p.produto_id, p.kg_pesar) e
    where e.item_id is not null
  ),
  diario as (
    select iid, dt, sum(kg) as kg_dia
    from detalhe
    group by iid, dt
  ),
  acumulado as (
    select iid, dt, kg_dia,
           sum(kg_dia) over (partition by iid order by dt) as kg_acumulado
    from diario
  ),
  nec as (
    select iid, sum(kg_dia) as kg, min(dt) as primeira_data
    from diario
    group by iid
  ),
  data_critica as (
    -- primeiro dia em que o consumo acumulado da programação pendente ultrapassa o saldo atual
    -- (corrige o viés antigo, que usava só o primeiro dia de uso do item)
    select a.iid, min(a.dt) as data_estouro
    from acumulado a
    join itens i on i.id = a.iid
    where a.kg_acumulado > i.saldo_atual
    group by a.iid
  ),
  caminho as (
    select c.item_id as iid, sum(c.quantidade_solicitada) as qtd
    from compras c where c.status in ('pendente','aguardando_pagamento','liberado')
    group by c.item_id
  )
  select i.id, i.nome, i.unidade,
    round(n.kg,2),
    i.saldo_atual, i.estoque_minimo,
    coalesce(cam.qtd,0) as a_caminho,
    round(greatest(0, n.kg + coalesce(i.estoque_minimo,0) - i.saldo_atual - coalesce(cam.qtd,0)),2) as a_comprar,
    i.lead_time_dias,
    coalesce(dc.data_estouro, n.primeira_data) as data_producao,
    case when i.lead_time_dias is null then null
         else (coalesce(dc.data_estouro, n.primeira_data) - (i.lead_time_dias + coalesce(v_margem,3))::int) end,
    case
      when greatest(0, n.kg + coalesce(i.estoque_minimo,0) - i.saldo_atual - coalesce(cam.qtd,0)) <= 0 then 'ok'
      when i.lead_time_dias is null then 'faltam dados'
      when (coalesce(dc.data_estouro, n.primeira_data) - (i.lead_time_dias + coalesce(v_margem,3))::int) <= current_date then 'PEDIR AGORA'
      when (coalesce(dc.data_estouro, n.primeira_data) - (i.lead_time_dias + coalesce(v_margem,3))::int) <= current_date + 7 then 'esta semana'
      else 'ok'
    end
  from nec n
  join itens i on i.id = n.iid
  left join caminho cam on cam.iid = n.iid
  left join data_critica dc on dc.iid = n.iid
  order by
    case when greatest(0, n.kg + coalesce(i.estoque_minimo,0) - i.saldo_atual - coalesce(cam.qtd,0)) <= 0 then 3
         when i.lead_time_dias is null then 2
         when (coalesce(dc.data_estouro, n.primeira_data) - (i.lead_time_dias + coalesce(v_margem,3))::int) <= current_date then 0
         else 1 end,
    i.nome;
end $function$
;

CREATE OR REPLACE FUNCTION public.iniciar_mistura(p_prog uuid, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_prod uuid; v_lote text; v_nome text;
begin
  select pr.produto_id, pr.lote into v_prod, v_lote
  from programacao_refino pr where pr.id=p_prog and pr.status='pesado' for update;
  if v_prod is null then raise exception 'Programação não encontrada ou não está em status pesado'; end if;
  update programacao_refino set status='mistura' where id=p_prog;
  select nome into v_nome from produtos where id=v_prod;
  insert into atividades(tipo,descricao,lote,responsavel) values ('mistura', format('Mistura iniciada — %s', v_nome), v_lote, p_responsavel);
end
$function$
;

CREATE OR REPLACE FUNCTION public.iniciar_refino(p_prog uuid, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_prod uuid; v_lote text; v_nome text;
begin
  select pr.produto_id, pr.lote into v_prod, v_lote
  from programacao_refino pr where pr.id=p_prog and pr.status='mistura' for update;
  if v_prod is null then raise exception 'Programação não encontrada ou não está em status mistura'; end if;
  update programacao_refino set status='refino' where id=p_prog;
  select nome into v_nome from produtos where id=v_prod;
  insert into atividades(tipo,descricao,lote,responsavel) values ('refino', format('Refino iniciado — %s', v_nome), v_lote, p_responsavel);
end
$function$
;

CREATE OR REPLACE FUNCTION public.verificar_pin(p_nome text, p_pin text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select exists(select 1 from operadores where nome = p_nome
                and (ativo or nome = 'Gestor')
                and pin_hash = crypt(p_pin, pin_hash));
$function$
;

-- ----------------------------------------------------------------------------
-- 7) RLS + POLÍTICAS — tudo "authenticated only" (login do app é a chave da porta)
-- ----------------------------------------------------------------------------
ALTER TABLE public.atividades ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compras ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demanda_vendas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.depara_sku ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.despachos_ecommerce ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.equipamentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estoque_balde ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estoque_balde_movimentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fornecedor_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fornecedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metas_dia ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operadores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parametros ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pesagem_lotes_mp ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produto_acabado ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produto_acabado_movimentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produtos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.programacao_refino ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quadro_recado ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receita_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tarefas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_all_atividades" ON public.atividades AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_compras" ON public.compras AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "demanda_all" ON public.demanda_vendas AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "depara_all" ON public.depara_sku AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_despachos" ON public.despachos_ecommerce AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_equip" ON public.equipamentos AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_estoque_balde" ON public.estoque_balde AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_estoque_balde_mov" ON public.estoque_balde_movimentos AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_fornecedor_itens" ON public.fornecedor_itens AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_fornecedores" ON public.fornecedores AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_itens" ON public.itens AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_metas" ON public.metas_dia AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_operadores" ON public.operadores AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_parametros" ON public.parametros AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_pes_lotes" ON public.pesagem_lotes_mp AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_pa" ON public.produto_acabado AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_pa_mov" ON public.produto_acabado_movimentos AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_produtos" ON public.produtos AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_prog" ON public.programacao_refino AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_recado" ON public.quadro_recado AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_receita_itens" ON public.receita_itens AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all_tarefas" ON public.tarefas AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ----------------------------------------------------------------------------
-- 8) BACKUP DIÁRIO (schema backup + snapshot diário, retenção 7 dias)
-- ⚠️ A lista abaixo é a que está em produção (16 tabelas). Pendência conhecida:
-- depara_sku, demanda_vendas, despachos_ecommerce, tarefas, metas_dia e
-- quadro_recado ainda NÃO entram no snapshot — incluir quando for aprovado.
-- ----------------------------------------------------------------------------
create schema if not exists backup;

CREATE OR REPLACE FUNCTION backup.fn_snapshot()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
  t text; sufixo text := to_char(now(),'YYYYMMDD'); r record;
begin
  foreach t in array array['itens','fornecedores','fornecedor_itens','produtos','receita_itens',
    'estoque_balde','estoque_balde_movimentos','produto_acabado','produto_acabado_movimentos',
    'compras','programacao_refino','pesagem_lotes_mp','atividades','equipamentos','operadores','parametros'] loop
    execute format('drop table if exists backup.%I', t||'_'||sufixo);
    execute format('create table backup.%I as select * from public.%I', t||'_'||sufixo, t);
  end loop;
  -- apaga fotos com mais de 7 dias
  for r in select tablename from pg_tables where schemaname='backup'
           and right(tablename,8) ~ '^[0-9]{8}$'
           and to_date(right(tablename,8),'YYYYMMDD') < current_date - 7 loop
    execute format('drop table backup.%I', r.tablename);
  end loop;
  insert into public.atividades(tipo, descricao, responsavel)
  values ('backup', 'Backup automático concluído — snapshot '||sufixo, 'sistema');
end $function$
;

-- Agendamento (rodar SÓ depois de habilitar a extensão pg_cron pelo painel):
-- select cron.schedule('backup-diario', '0 6 * * *', 'select backup.fn_snapshot()');

-- ----------------------------------------------------------------------------
-- 9) DADOS-SEMENTE MÍNIMOS (obrigatórios pro motor funcionar)
-- Os demais dados (itens, produtos, receitas, saldos...) vêm do último
-- snapshot do schema backup ou de recadastro — ver RECUPERACAO.md.
-- ----------------------------------------------------------------------------
insert into public.parametros(chave, valor) values
  ('perda_processo_pct', 3),
  ('margem_seguranca_dias', 3)
on conflict (chave) do nothing;

insert into public.equipamentos(nome, ativo) values
  ('Moinho 1', true),
  ('Moinho 2', true)
on conflict do nothing;

-- Operadores reais + Gestor (o PIN do Gestor NÃO está neste arquivo de propósito;
-- o valor está no documento-mestre do projeto. Recriar assim, trocando 0000:
-- insert into public.operadores(nome, ativo, pin_hash)
--   values ('Gestor', false, crypt('0000', gen_salt('bf')));
insert into public.operadores(nome, ativo) values
  ('Andréia', true), ('Janaína', true), ('Jean', true), ('Le', true),
  ('Lucia', true), ('Patrícia', true), ('Sabrina', true)
on conflict (nome) do nothing;

-- ============================================================================
-- FIM. Checklist pós-restauração: ver RECUPERACAO.md na raiz do repositório.
-- ============================================================================
