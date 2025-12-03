{{ config(materialized='table') }}

with base as (
    select
        c.id as customer_id,
        c.customer_name,
        c.segment,
        o.order_id,
        o.order_date,
        sum(coalesce(oi.sales,0)) as order_amount
    from customers c
    left join orders o on o.customer_id = c.id
    left join order_item oi on oi.order_id = o.order_id
    group by 1,2,3,4,5
),

agg as (
    select
        customer_id,
        customer_name,
        segment,

        -- RFM components
        datediff('day', max(order_date), current_date) as recency,
        count(distinct order_id) as frequency,
        sum(order_amount) as monetary,

        -- lifetime metrics
        min(order_date) as first_order_date,
        max(order_date) as last_order_date,
        sum(order_amount) as lifetime_revenue,

        -- time-based customer age
        datediff('day', min(order_date), current_date) as customer_age_days
    from base
    group by 1,2,3
),

rfm_scores as (
    select
        *,
        -- RFM scoring using NTILE() distribution into 5 buckets
        ntile(5) over (order by recency asc) as recency_score,    -- lower recency = better score
        ntile(5) over (order by frequency desc) as frequency_score,
        ntile(5) over (order by monetary desc) as monetary_score
    from agg
),

final as (
    select
        customer_id,
        customer_name,
        segment,

        recency,
        frequency,
        monetary,
        lifetime_revenue,
        first_order_date,
        last_order_date,
        customer_age_days,

        recency_score,
        frequency_score,
        monetary_score,

        (recency_score + frequency_score + monetary_score) as rfm_total_score,

        -- Cohort (YYYY-MM formatted)
        to_char(first_order_date, 'YYYY-MM') as cohort_month,

        -- Classification
        case
            when lifetime_revenue >= 5000 then 'High Value'
            when lifetime_revenue between 2000 and 4999 then 'Mid Value'
            else 'Low Value'
        end as value_segment,

        -- Churn risk: no orders in last 90+ days
        case
            when recency > 120 then 'High Risk'
            when recency between 61 and 120 then 'Medium Risk'
            when recency <= 60 then 'Low Risk'
            else 'Unknown'
        end as churn_risk

    from rfm_scores
)

select * from final
order by rfm_total_score desc, lifetime_revenue desc
