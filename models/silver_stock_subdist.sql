{{ config(materialized='table') }}

select vtd.year, mc.period, vtd.week, vtd.sub_id as distributor_id, vtd.pcode, vtd.qty
from spx.v_stock_dist vtd
join (select distinct year, week, period from spx.m_cycle3) mc
    on vtd.year = mc.year and vtd.week = mc.week