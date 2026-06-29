{{ config(materialized='table') }}

with cycle_week as (
  select distinct year, period, to_char(to_date(cast(period as text), 'MM'), 'Mon') as periodName,  week, 
  	case when year = EXTRACT(YEAR FROM CURRENT_DATE) then 'cy'
  		 when year = EXTRACT(YEAR FROM CURRENT_DATE) -1 then 'ly'
  	end as flag
  from spx.m_cycle3
	WHERE year >= EXTRACT(YEAR FROM CURRENT_DATE) - 1 and year <= EXTRACT(YEAR FROM CURRENT_DATE)
)	
select md.sls_div as channel, cw.year, cw.period, cw.periodname, cw.week, cw.flag,
	vsh.nsm_id, vsh.nsm_name, vsh.grsm_id, vsh.grsm_name, vsh.rsm_id, vsh.rsm_name, vsh.ss_id, vsh.ss_name,
	mp.div_id as sbu_id, mp.div_nm as sbu_name, mp.brand_id, mp.brand_nm as brand_name, mp.subbrand_id, mp.subbrand_nm as subbrand_name, mp.parent_id, mp.parent_nm as parent_name, 
	mp.pcode, mp.pcodename, mp.flag_season as flag_sku,
	ttw.distributor_id, md.distributor_nm as distributor_name, ttw.target_qty,  ttw.target_value
	, vosbw.omsetqty as stm_qty, vosbw.omsetvalue as stm_value
	,vscw.qty as salfo_qty, vscw.qty * coalesce(mpd.price,0) as salfo_value
FROM cycle_week cw join spx.t_target_weekly ttw on  cw.year = ttw.year and cw.week = ttw.week
left join (select pcode, pcodename, p.div_id, md.div_nm, p.brand_id, mb.brand_nm, p.subbrand_id, ms.subbrand_nm, p.parent_id,mp.parent_nm, flag_season 
	from spx.m_product p left join spx.m_division md on p.div_id = md.div_id
	left join spx.m_brand mb on p.brand_id = mb.brand_id
	left join spx.m_subbrand ms on p.brand_id = ms.brand_id and p.subbrand_id = ms.subbrand_id 
	left join spx.m_parent mp on p.parent_id = mp.parent_id) mp on ttw.pcode = mp.pcode 
	left join spx.v_sales_hierarchy vsh on ttw.distributor_id = vsh.distributor_id
	join spx.m_emp_team met on met.distributor_id = ttw.distributor_id and met.emp_id = vsh.ss_id
	join spx.m_team tm ON met.team_id = tm.team_id and mp.div_id = tm.div_id
	left join spx.m_distributor md on ttw.distributor_id = md.distributor_id
	left join spx.v_salfo_confirm_weekly vscw on cw.year = vscw.year and cw.week = vscw.week and ttw.pcode = vscw.pcode and ttw.distributor_id = vscw.distributor_id
	left join spx.v_omset_subdist_weekly_bw vosbw on cw.year = cast(vosbw.tahun as numeric) and cw.week = cast(vosbw.week as numeric) and cw.period = cast(vosbw.periode as numeric) and ttw.pcode = vosbw.pcode and ttw.distributor_id = vosbw.distributor_id
	left join spx.m_price_divisi mpd on cw.year = mpd.year and ttw.pcode = mpd.pcode and md.sls_div = mpd.sls_div