/*
 * Часть 2. Ad hoc задачи
 * Задача 2. Сезонность публикации и снятия объявлений
 *
 * В какие месяцы чаще всего выставляют квартиры на продажу и в какие —
 * снимают объявления. Отдельно смотрим, различаются ли объекты, попадающие
 * в эти месяцы, по цене метра и площади.
 *
 * Месяц снятия вычисляется как дата публикации плюс срок экспозиции.
 * Период: 2015–2018 годы, только населённые пункты типа «город».
 */

-- Русские названия месяцев в TO_CHAR(..., 'TMmon').
SET lc_time = 'ru_RU';

WITH
-- Границы выбросов — те же, что и в задаче 1.
limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area)     AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms)          AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony)        AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),

filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE total_area < (SELECT total_area_limit FROM limits)
      AND (rooms   < (SELECT rooms_limit   FROM limits) OR rooms   IS NULL)
      AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
      AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
           OR ceiling_height IS NULL)
),

-- Объявления с вычисленными месяцами публикации и снятия.
ads AS (
    SELECT
        a.id,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.total_area,
        a.last_price / f.total_area AS price_per_m2,
        EXTRACT(MONTH FROM a.first_day_exposition) AS publish_month,
        EXTRACT(
            MONTH FROM a.first_day_exposition + (a.days_exposition::INT * INTERVAL '1 day')
        ) AS unpublish_month
    FROM real_estate.advertisement AS a
    LEFT JOIN real_estate.flats AS f ON a.id = f.id
    JOIN real_estate.type AS t ON f.type_id = t.type_id
    WHERE a.id IN (SELECT id FROM filtered_id)
      AND t.type = 'город'
      AND a.first_day_exposition >= '2015-01-01'
      AND a.first_day_exposition <  '2019-01-01'
),

-- Полный список месяцев: объединяем месяцы публикации и снятия,
-- чтобы ни один не потерялся, если в нём была только одна из операций.
months AS (
    SELECT DISTINCT publish_month AS month FROM ads
    UNION
    SELECT DISTINCT unpublish_month AS month FROM ads
)

-- По каждому месяцу: сколько объявлений открыто и закрыто,
-- и какие в среднем цена метра и площадь у тех и у других.
SELECT
    TO_CHAR(TO_DATE(m.month::TEXT, 'MM'), 'TMmon') AS month_name,
    COUNT(CASE WHEN a.publish_month   = m.month THEN a.id END) AS published_ads,
    COUNT(CASE WHEN a.unpublish_month = m.month THEN a.id END) AS unpublished_ads,
    ROUND(AVG(CASE WHEN a.publish_month   = m.month THEN a.last_price / a.total_area END)::NUMERIC, 2)
        AS published_avg_price_per_m2,
    ROUND(AVG(CASE WHEN a.unpublish_month = m.month THEN a.last_price / a.total_area END)::NUMERIC, 2)
        AS unpublished_avg_price_per_m2,
    ROUND(AVG(CASE WHEN a.publish_month   = m.month THEN a.total_area END)::NUMERIC, 0)
        AS published_avg_total_area,
    ROUND(AVG(CASE WHEN a.unpublish_month = m.month THEN a.total_area END)::NUMERIC, 0)
        AS unpublished_avg_total_area
FROM months AS m
LEFT JOIN ads AS a
    ON a.publish_month   = m.month
    OR a.unpublish_month = m.month
GROUP BY m.month
ORDER BY m.month;
