-- Nutríssima — fonte das funções do banco (schema public)
-- Extraído de produção (projeto nfzospymzvlwzlcpgolm) em 12/07/2026.
-- Regra: toda alteração de função em produção deve ser refletida aqui no mesmo dia.

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
end $function$;

---------------------------------------------

CREATE OR REPLACE FUNCTION public.concluir_refino(p_prog uuid, p_qtd_real numeric, p_responsavel text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare v_prod uuid; v_lote text; v_nome text; v_estocavel boolean;
begin
  select pr.produto_id, pr.lote, p.nome, p.estocavel_balde into v_prod, v_lote, v_nome, v_estocavel
  from programacao_refino pr join produtos p on p.id=pr.produto_id where pr.id=p_prog and pr.status='pesado' for update;
  if v_prod is null then raise exception 'Programação não encontrada ou ainda não pesada'; end if;
  if v_estocavel then
    insert into estoque_balde(produto_id,quantidade_kg) values (v_prod,p_qtd_real)
      on conflict (produto_id) do update set quantidade_kg = estoque_balde.quantidade_kg + p_qtd_real, atualizado_em=now();
    insert into estoque_balde_movimentos(produto_id,tipo,quantidade_kg,lote,responsavel) values (v_prod,'entrada',p_qtd_real,v_lote,p_responsavel);
  end if;
  update programacao_refino set status='no_balde' where id=p_prog;
  insert into atividades(tipo,descricao,lote,responsavel) values ('refino', format('Refino concluído — %s kg de %s no balde', round(p_qtd_real,1), v_nome), v_lote, p_responsavel);
end $function$;

---------------------------------------------

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
end $function$;

---------------------------------------------

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
end $function$;

---------------------------------------------

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
end $function$;

---------------------------------------------

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
$function$;

---------------------------------------------

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
end $function$;

---------------------------------------------

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
  nec as (
    select e.item_id as iid, sum(e.kg) as kg, min(p.data) as primeira_data
    from pend p cross join lateral fn_explode(p.produto_id, p.kg_pesar) e
    where e.item_id is not null
    group by e.item_id
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
    n.primeira_data,
    case when i.lead_time_dias is null then null
         else (n.primeira_data - (i.lead_time_dias + coalesce(v_margem,3))::int) end,
    case
      when greatest(0, n.kg + coalesce(i.estoque_minimo,0) - i.saldo_atual - coalesce(cam.qtd,0)) <= 0 then 'ok'
      when i.lead_time_dias is null then 'faltam dados'
      when (n.primeira_data - (i.lead_time_dias + coalesce(v_margem,3))::int) <= current_date then 'PEDIR AGORA'
      when (n.primeira_data - (i.lead_time_dias + coalesce(v_margem,3))::int) <= current_date + 7 then 'esta semana'
      else 'ok'
    end
  from nec n
  join itens i on i.id = n.iid
  left join caminho cam on cam.iid = n.iid
  order by
    case when greatest(0, n.kg + coalesce(i.estoque_minimo,0) - i.saldo_atual - coalesce(cam.qtd,0)) <= 0 then 3
         when i.lead_time_dias is null then 2
         when (n.primeira_data - (i.lead_time_dias + coalesce(v_margem,3))::int) <= current_date then 0
         else 1 end,
    i.nome;
end $function$;

---------------------------------------------

CREATE OR REPLACE FUNCTION public.verificar_pin(p_nome text, p_pin text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select exists(select 1 from operadores where nome = p_nome
                and (ativo or nome = 'Gestor')
                and pin_hash = crypt(p_pin, pin_hash));
$function$;
