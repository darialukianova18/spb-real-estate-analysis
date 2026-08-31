/*
 * Часть 1. Исследовательский анализ данных
 *
 * Цель блока — понять, с чем мы имеем дело: за какой период собраны данные,
 * как они распределены по типам населённых пунктов, сколько объявлений
 * закрыто, и какие значения считать выбросами.
 *
 * СУБД: PostgreSQL, схема real_estate
 */


-- 1. Границы периода наблюдения
-- За какой промежуток времени собраны объявления.
SELECT
    MIN(first_day_exposition) AS min_date,
    MAX(first_day_exposition) AS max_date
FROM real_estate.advertisement;


-- 2. Структура рынка по типам населённых пунктов
-- Сколько населённых пунктов каждого типа и сколько в них объявлений.
SELECT
    t.type                        AS village_type,
    COUNT(DISTINCT c.city_id)     AS village_count,
    COUNT(f.id)                   AS ads_count
FROM real_estate.flats AS f
JOIN real_estate.city AS c ON f.city_id = c.city_id
JOIN real_estate.type AS t ON f.type_id = t.type_id
GROUP BY t.type
ORDER BY ads_count DESC;


-- 3. Сроки экспозиции объявлений
-- Минимум, максимум, среднее и медиана времени до снятия объявления.
-- Медиана важнее среднего: распределение скошено вправо.
SELECT
    MIN(days_exposition)                    AS min_days,
    MAX(days_exposition)                    AS max_days,
    ROUND(AVG(days_exposition::NUMERIC), 2) AS avg_days,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY days_exposition::DOUBLE PRECISION
    )                                       AS median_days
FROM real_estate.advertisement;


-- 4. Доля снятых объявлений
-- COUNT(колонка) не считает NULL, COUNT(*) считает все строки.
-- Пустой days_exposition означает, что объявление ещё активно.
SELECT
    ROUND(100.0 * COUNT(days_exposition) / COUNT(*), 2) AS removed_percent
FROM real_estate.advertisement;


-- 5. Доля объявлений по Санкт-Петербургу
-- Насколько выборка смещена в сторону города относительно области.
SELECT
    ROUND(
        100.0 * COUNT(f.id) FILTER (WHERE c.city = 'Санкт-Петербург')
        / COUNT(f.id), 2
    ) AS spb_percent
FROM real_estate.flats AS f
JOIN real_estate.city AS c ON f.city_id = c.city_id;


-- 6. Стоимость квадратного метра
-- Нулевые площадь и цена отсекаются: это заведомо некорректные записи.
SELECT
    ROUND(MIN((a.last_price / f.total_area)::NUMERIC), 2) AS min_price_per_sqm,
    ROUND(MAX((a.last_price / f.total_area)::NUMERIC), 2) AS max_price_per_sqm,
    ROUND(AVG((a.last_price / f.total_area)::NUMERIC), 2) AS avg_price_per_sqm,
    ROUND(
        (PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY (a.last_price / f.total_area)::DOUBLE PRECISION
        )::NUMERIC), 2
    ) AS median_price_per_sqm
FROM real_estate.flats AS f
JOIN real_estate.advertisement AS a ON f.id = a.id
WHERE total_area > 0
  AND last_price > 0;


-- 7. Характеристики квартир и границы выбросов
-- По каждому признаку: минимум, максимум, среднее, медиана и 99-й перцентиль.
-- Перцентиль нужен, чтобы задать порог отсечения аномалий в части 2.
-- Порог непараметрический: распределения скошены, правило трёх сигм не подходит.
SELECT
    -- Общая площадь
    ROUND(MIN(total_area)::NUMERIC, 2) AS min_total_area,
    ROUND(MAX(total_area)::NUMERIC, 2) AS max_total_area,
    ROUND(AVG(total_area)::NUMERIC, 2) AS avg_total_area,
    ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY total_area)::NUMERIC, 2) AS median_total_area,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area)::NUMERIC, 2) AS perc_total_area,

    -- Количество комнат
    ROUND(MIN(rooms)::NUMERIC, 2) AS min_rooms,
    ROUND(MAX(rooms)::NUMERIC, 2) AS max_rooms,
    ROUND(AVG(rooms)::NUMERIC, 2) AS avg_rooms,
    ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY rooms)::NUMERIC, 2) AS median_rooms,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY rooms)::NUMERIC, 2) AS perc_rooms,

    -- Количество балконов
    ROUND(MIN(balcony)::NUMERIC, 2) AS min_balcony,
    ROUND(MAX(balcony)::NUMERIC, 2) AS max_balcony,
    ROUND(AVG(balcony)::NUMERIC, 2) AS avg_balcony,
    ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY balcony)::NUMERIC, 2) AS median_balcony,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY balcony)::NUMERIC, 2) AS perc_balcony,

    -- Высота потолков
    ROUND(MIN(ceiling_height)::NUMERIC, 2) AS min_ceiling_height,
    ROUND(MAX(ceiling_height)::NUMERIC, 2) AS max_ceiling_height,
    ROUND(AVG(ceiling_height)::NUMERIC, 2) AS avg_ceiling_height,
    ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY ceiling_height)::NUMERIC, 2) AS median_ceiling_height,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height)::NUMERIC, 2) AS perc_ceiling_height,

    -- Этаж
    ROUND(MIN(floor)::NUMERIC, 2) AS min_floor,
    ROUND(MAX(floor)::NUMERIC, 2) AS max_floor,
    ROUND(AVG(floor)::NUMERIC, 2) AS avg_floor,
    ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY floor)::NUMERIC, 2) AS median_floor,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY floor)::NUMERIC, 2) AS perc_floor
FROM real_estate.flats
WHERE total_area > 0
  AND rooms > 0
  AND ceiling_height > 0
  AND floor >= 0;
