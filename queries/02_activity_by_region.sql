/*
 * Часть 2. Ad hoc задачи
 * Задача 1. Время активности объявлений
 *
 * Заказчику нужно понять, какие сегменты рынка привлекательнее для работы.
 * Сравниваем Санкт-Петербург и Ленинградскую область по тому, как быстро
 * продаются квартиры, и чем отличаются объекты в каждой группе по срокам.
 *
 * Период: 2015–2018 годы целиком. 2014 и 2019 отброшены как неполные.
 * Рассматриваются только населённые пункты типа «город».
 */

WITH
-- Границы выбросов по 99-му перцентилю.
-- Для дискретных признаков (комнаты, балконы) берём PERCENTILE_DISC:
-- дробное число комнат не имеет смысла.
-- Для высоты потолков отсекаем с двух сторон — встречаются и нулевые значения.
limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area)     AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms)          AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony)        AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),

-- Идентификаторы объявлений без выбросов.
-- NULL сохраняем: пропуск в поле не означает аномалию.
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

-- Количество объявлений по региону и категории срока активности.
sales AS (
    SELECT
        CASE
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS region,
        CASE
            WHEN days_exposition <= 30                 THEN '1-30 days'
            WHEN days_exposition BETWEEN 31  AND 90    THEN '31-90 days'
            WHEN days_exposition BETWEEN 91  AND 180   THEN '91-180 days'
            WHEN days_exposition >= 181                THEN '181+ days'
            ELSE 'non category'
        END AS activity_category,
        COUNT(a.id) AS total_count
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f USING (id)
    JOIN real_estate.type  AS t ON f.type_id = t.type_id
    JOIN real_estate.city  AS c USING (city_id)
    WHERE a.id IN (SELECT id FROM filtered_id)
      AND t.type = 'город'
      AND first_day_exposition >= '2015-01-01'
      AND first_day_exposition <  '2019-01-01'
    GROUP BY region, activity_category
),

-- Характеристики объектов внутри тех же групп: цена метра, площадь, медианы.
details AS (
    SELECT
        CASE
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS region,
        CASE
            WHEN days_exposition <= 30                 THEN '1-30 days'
            WHEN days_exposition BETWEEN 31  AND 90    THEN '31-90 days'
            WHEN days_exposition BETWEEN 91  AND 180   THEN '91-180 days'
            WHEN days_exposition >= 181                THEN '181+ days'
            ELSE 'non category'
        END AS activity_category,
        ROUND(AVG(CAST(last_price / total_area AS DECIMAL(10, 2))), 0) AS price_per_m2,
        ROUND(AVG(CAST(total_area AS DECIMAL(10, 2))), 0)              AS avg_total_area,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rooms)             AS median_rooms,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY balcony)           AS median_balcony,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ceiling_height)    AS median_ceiling_height,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY floor)             AS median_floor
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f USING (id)
    JOIN real_estate.type  AS t ON f.type_id = t.type_id
    JOIN real_estate.city  AS c USING (city_id)
    WHERE a.id IN (SELECT id FROM filtered_id)
      AND t.type = 'город'
      AND first_day_exposition >= '2015-01-01'
      AND first_day_exposition <  '2019-01-01'
    GROUP BY region, activity_category
)

-- Итог: доля каждой категории внутри своего региона считается оконной функцией —
-- SUM(...) OVER (PARTITION BY region) даёт итог по региону, не схлопывая строки.
SELECT
    s.region,
    s.activity_category,
    s.total_count,
    ROUND(
        s.total_count::DECIMAL / SUM(s.total_count) OVER (PARTITION BY s.region) * 100, 2
    ) AS share_in_region,
    d.price_per_m2,
    d.avg_total_area,
    d.median_rooms,
    d.median_balcony,
    d.median_floor
FROM sales AS s
JOIN details AS d
    ON  s.region            = d.region
    AND s.activity_category = d.activity_category
-- Сортировка не алфавитная, а смысловая: сначала город, затем область;
-- категории — по возрастанию срока продажи.
ORDER BY
    CASE s.region
        WHEN 'Санкт-Петербург' THEN 1
        ELSE 2
    END,
    CASE s.activity_category
        WHEN '1-30 days'   THEN 1
        WHEN '31-90 days'  THEN 2
        WHEN '91-180 days' THEN 3
        WHEN '181+ days'   THEN 4
        ELSE 5
    END;
