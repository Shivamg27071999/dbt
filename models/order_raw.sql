select * from products
select * from order_item o;
inner join products p on p.id = o.PRODUCT_ID;

-- Daily sales & order count trend (top-level KPI)
select
    order_date::date as order_date,
    count(distinct o.order_id) as orders_count,
    sum(oi.sales) as total_sales,
    round(sum(oi.sales) / nullif(count(distinct o.order_id),0), 2) as aov
from orders o
left join order_item oi on oi.order_id = o.order_id
group by 1
order by 1


--2) Top 10 Customers by Revenue
select
    c.id as customer_id,
    c.customer_name,
    c.segment,
    sum(coalesce(oi.sales,0)) as lifetime_sales,
    count(distinct o.order_id) as orders_count
from customers c
left join orders o on o.customer_id = c.id
left join order_item oi on oi.order_id = o.order_id
group by 1,2,3
order by lifetime_sales desc

-- 3) Top Products by Revenue — dbt-safe version
select
    p.id as product_id,
    p.product_name,
    sum(coalesce(oi.quantity,0)) as total_qty,
    sum(coalesce(oi.sales,0)) as total_sales
from products p
left join order_item oi on oi.product_id = p.id
group by 1,2
order by total_sales desc


-- Sales by Category & Sub-Category — dbt-safe version
select
    sc.category,
    sc.sub_category,
    sum(coalesce(oi.sales,0)) as revenue
from subcatagories sc
left join products pr on pr.sub_category_id = sc.id
left join order_item oi on oi.product_id = pr.id
group by 1,2
order by revenue desc


--5 ) AOV Percentiles (Median / P75 / P90) — dbt-safe version
with totals as (
    select
        o.order_id,
        sum(coalesce(oi.sales,0)) as order_total
    from orders o
    left join order_item oi on oi.order_id = o.order_id
    group by 1
)
select
    percentile_cont(0.50) within group (order by order_total) as p50,
    percentile_cont(0.75) within group (order by order_total) as p75,
    percentile_cont(0.90) within group (order by order_total) as p90,
    avg(order_total) as avg_order_total
from totals






--Query 6 — Repeat Purchase Rate, dbt-safe (no semicolon, no LIMIT)
with cust_orders as (
    select
        customer_id,
        count(distinct order_id) as orders_count
    from orders
    group by 1
)
select
    sum(case when orders_count > 1 then 1 else 0 end) as repeat_customers,
    count(*) as total_customers,
    round(100.0 * sum(case when orders_count > 1 then 1 else 0 end) / nullif(count(*),0), 2) as repeat_rate_pct,
    round(avg(orders_count),2) as avg_orders_per_customer
from cust_orders


-- Query 7 — Discount Impact on Order Value, dbt-safe (no semicolon, no LIMIT)
with joined as (
    select
        o.order_id,
        coalesce(o.discount,0) as discount,
        sum(coalesce(oi.sales,0)) as order_sales,
        sum(coalesce(oi.quantity,0)) as units_sold
    from orders o
    left join order_item oi on oi.order_id = o.order_id
    group by 1,2
)
select
    case
        when discount = 0 then '0%'
        when discount <= 0.10 then '0–10%'
        when discount <= 0.25 then '10–25%'
        when discount <= 0.50 then '25–50%'
        else '50%+'
    end as discount_band,
    count(*) as orders_count,
    sum(order_sales) as revenue,
    sum(units_sold) as units_sold,
    round(avg(order_sales),2) as avg_order_sales
from joined
group by 1
order by revenue desc



--Query 8 — Shipping Lag Performance, dbt-safe (no semicolon, no LIMIT). It reports avg & median
select
    s.ship_mode,
    count(distinct s.order_id) as orders_shipped,
    round(avg(datediff('day', o.order_date, s.ship_date)),2) as avg_ship_lag_days,
    percentile_cont(0.5) within group (order by datediff('day', o.order_date, s.ship_date)) as median_ship_lag_days,
    percentile_cont(0.9) within group (order by datediff('day', o.order_date, s.ship_date)) as p90_ship_lag_days,
    min(datediff('day', o.order_date, s.ship_date)) as min_ship_lag_days,
    max(datediff('day', o.order_date, s.ship_date)) as max_ship_lag_days
from shipments s
left join orders o on o.order_id = s.order_id
where s.ship_date is not null
  and o.order_date is not null
group by 1
order by avg_ship_lag_days

-- Query 9 — Revenue by City / State / Region, dbt-safe (no semicolon, no LIMIT
select
    ct.region,
    ct.state,
    ct.city,
    sum(coalesce(oi.sales,0)) as revenue,
    count(distinct o.order_id) as orders_count
from cities ct
left join pincodes pc on pc.city_id = ct.id
left join customers c on c.pincode_id = pc.id
left join orders o on o.customer_id = c.id
left join order_item oi on oi.order_id = o.order_id
group by 1,2,3
order by revenue desc


-- Query 10 — Segment-Level Lifetime Value (Simple LTV Proxy), dbt-safe
with cust_sales as (
    select
        c.segment,
        c.id as customer_id,
        sum(coalesce(oi.sales,0)) as lifetime_revenue,
        count(distinct o.order_id) as orders_count
    from customers c
    left join orders o on o.customer_id = c.id
    left join order_item oi on oi.order_id = o.order_id
    group by 1,2
)
select
    segment,
    round(avg(lifetime_revenue),2) as avg_ltv,
    round(avg(orders_count),2) as avg_orders_per_customer,
    count(*) as customers,
    round(sum(lifetime_revenue),2) as total_revenue
from cust_sales
group by 1
order by avg_ltv desc



