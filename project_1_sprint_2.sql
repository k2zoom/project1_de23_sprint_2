
/* создание таблицы tmp_sources с данными из всех источников */
DROP TABLE IF EXISTS tmp_sources;
CREATE table if not exists dwh.tmp_sources AS 
SELECT  order_id,
        order_created_date,
        order_completion_date,
        order_status,
        craftsman_id,
        craftsman_name,
        craftsman_address,
        craftsman_birthday,
        craftsman_email,
        product_id,
        product_name,
        product_description,
        product_type,
        product_price,
        customer_id,
        customer_name,
        customer_address,
        customer_birthday,
        customer_email 
  FROM source1.craft_market_wide
UNION
SELECT  t2.order_id,
        t2.order_created_date,
        t2.order_completion_date,
        t2.order_status,
        t1.craftsman_id,
        t1.craftsman_name,
        t1.craftsman_address,
        t1.craftsman_birthday,
        t1.craftsman_email,
        t1.product_id,
        t1.product_name,
        t1.product_description,
        t1.product_type,
        t1.product_price,
        t2.customer_id,
        t2.customer_name,
        t2.customer_address,
        t2.customer_birthday,
        t2.customer_email 
  FROM source2.craft_market_masters_products t1 
    JOIN source2.craft_market_orders_customers t2 
    ON t2.product_id = t1.product_id and t1.craftsman_id = t2.craftsman_id 
UNION
SELECT  t1.order_id,
        t1.order_created_date,
        t1.order_completion_date,
        t1.order_status,
        t2.craftsman_id,
        t2.craftsman_name,
        t2.craftsman_address,
        t2.craftsman_birthday,
        t2.craftsman_email,
        t1.product_id,
        t1.product_name,
        t1.product_description,
        t1.product_type,
        t1.product_price,
        t3.customer_id,
        t3.customer_name,
        t3.customer_address,
        t3.customer_birthday,
        t3.customer_email
  FROM source3.craft_market_orders t1
    JOIN source3.craft_market_craftsmans t2 ON t1.craftsman_id = t2.craftsman_id 
    JOIN source3.craft_market_customers t3 ON t1.customer_id = t3.customer_id
union
   select cpo.order_id,
   cpo.order_created_date,
   cpo.order_completion_date,
   cpo.order_status,
   cpo.craftsman_id,
   cpo.craftsman_name ,
   cpo.craftsman_address,
   cpo.craftsman_birthday,
   cpo.craftsman_email,
   cpo.product_id,
   cpo.product_name,
   cpo.product_description,
   cpo.product_type,
   cpo.product_price,
   c.customer_id,
   c.customer_name,
   c.customer_address,
   c.customer_birthday,
   c.customer_email
   from external_source.craft_products_orders cpo
   join external_source.customers c on c.customer_id=cpo.customer_id
   
/* обновление существующих записей и добавление новых в dwh.d_craftsmans */
MERGE INTO dwh.d_craftsman d
USING (SELECT DISTINCT craftsman_name, craftsman_address, craftsman_birthday, craftsman_email FROM dwh.tmp_sources) t
ON d.craftsman_name = t.craftsman_name AND d.craftsman_email = t.craftsman_email
WHEN MATCHED THEN
  UPDATE SET craftsman_address = t.craftsman_address, 
craftsman_birthday = t.craftsman_birthday, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (craftsman_name, craftsman_address, craftsman_birthday, craftsman_email, load_dttm)
  VALUES (t.craftsman_name, t.craftsman_address, t.craftsman_birthday, t.craftsman_email, current_timestamp);

/* обновление существующих записей и добавление новых в dwh.d_products */
MERGE INTO dwh.d_product d
USING (SELECT DISTINCT product_name, product_description, product_type, product_price from dwh.tmp_sources) t
ON d.product_name = t.product_name AND d.product_description = t.product_description AND d.product_price = t.product_price
WHEN MATCHED THEN
  UPDATE SET product_type= t.product_type, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (product_name, product_description, product_type, product_price, load_dttm)
  VALUES (t.product_name, t.product_description, t.product_type, t.product_price, current_timestamp);

/* обновление существующих записей и добавление новых в dwh.d_customer */
MERGE INTO dwh.d_customer d
USING (SELECT DISTINCT customer_name, customer_address, customer_birthday, customer_email from dwh.tmp_sources) t
ON d.customer_name = t.customer_name AND d.customer_email = t.customer_email
WHEN MATCHED THEN
  UPDATE SET customer_address= t.customer_address, 
customer_birthday= t.customer_birthday, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (customer_name, customer_address, customer_birthday, customer_email, load_dttm)
  VALUES (t.customer_name, t.customer_address, t.customer_birthday, t.customer_email, current_timestamp);

/* создание таблицы tmp_sources_fact */
DROP TABLE IF EXISTS tmp_sources_fact;
CREATE table if not exists dwh.tmp_sources_fact AS 
SELECT  dp.product_id,
        dc.craftsman_id,
        dcust.customer_id,
        src.order_created_date,
        src.order_completion_date,
        src.order_status,
        current_timestamp 
FROM dwh.tmp_sources src
JOIN dwh.d_craftsman dc ON dc.craftsman_name = src.craftsman_name and dc.craftsman_email = src.craftsman_email 
JOIN dwh.d_customer dcust ON dcust.customer_name = src.customer_name and dcust.customer_email = src.customer_email 
JOIN dwh.d_product dp ON dp.product_name = src.product_name and dp.product_description = src.product_description and dp.product_price = src.product_price;

/* обновление существующих записей и добавление новых в dwh.f_order */
MERGE INTO dwh.f_order f
USING dwh.tmp_sources_fact t
ON f.product_id = t.product_id AND f.craftsman_id = t.craftsman_id AND f.customer_id = t.customer_id AND f.order_created_date = t.order_created_date 
WHEN MATCHED THEN
  UPDATE SET order_completion_date = t.order_completion_date, order_status = t.order_status, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (product_id, craftsman_id, customer_id, order_created_date, order_completion_date, order_status, load_dttm)
  VALUES (t.product_id, t.craftsman_id, t.customer_id, t.order_created_date, t.order_completion_date, t.order_status, current_timestamp);
  
DROP TABLE IF EXISTS dwh.customer_report_datamart;

CREATE TABLE IF NOT EXISTS dwh.customer_report_datamart (
    id BIGINT GENERATED ALWAYS AS IDENTITY NOT NULL, -- идентификатор записи
    customer_id BIGINT NOT NULL, -- идентификатор заказчика
    customer_name VARCHAR NOT NULL, -- Ф. И. О. заказчика
    customer_address VARCHAR NOT NULL, -- его адрес
    customer_birthday DATE NOT NULL, -- дата рождения
    customer_email VARCHAR NOT NULL, -- электронная почта
    customer_money BIGINT NOT NULL, -- сумма денег, которую потратил заказчик 
    platform_customer_money BIGINT NOT NULL, -- сумма денег, которая заработала платформа с покупок заказчика за месяц 
    count_customer_order BIGINT NOT NULL, -- количество заказов у покупателя за месяц
    avg_price_customer_order NUMERIC(10,2) NOT NULL, -- средняя стоимость одного заказа у покупателя за месяц
    median_time_customer_order_completed NUMERIC(10,1), -- медианное время в днях от момента создания заказа до его завершения за месяц
    top_product_customer_category VARCHAR NOT NULL, -- самая популярная категория товаров у этого заказчика за месяц
    top_craftsman_customer BIGINT not null, --идентификатор самого популярного мастера ручной работы у заказчика. Если заказчик сделал одинаковое количество заказов у нескольких мастеров, возьмите любого
    count_customer_order_created BIGINT NOT NULL, -- количество созданных заказов за месяц
    count_customer_order_in_progress BIGINT NOT NULL, -- количество заказов в процессе изготовки за месяц
    count_customer_order_delivery BIGINT NOT NULL, -- количество заказов в доставке за месяц
    count_customer_order_done BIGINT NOT NULL, -- количество завершённых заказов за месяц
    count_customer_order_not_done BIGINT NOT NULL, -- количество незавершённых заказов за месяц
    report_customer_period VARCHAR NOT NULL, -- отчётный период (год и месяц)
    CONSTRAINT customer_report_datamart_pk PRIMARY KEY (id)
); 

DROP TABLE IF EXISTS dwh.load_dates_customer_report_datamart;

CREATE TABLE IF NOT EXISTS dwh.load_dates_customer_report_datamart (
    id BIGINT GENERATED ALWAYS AS IDENTITY NOT NULL,
    load_dttm DATE NOT NULL,
    CONSTRAINT load_dates_customer_report_datamart_pk PRIMARY KEY (id));
   
   
   
WITH
dwh_customer_delta AS ( -- определяем, какие данные были изменены в витрине или добавлены в DWH. Формируем дельту изменений
    SELECT     
            dcs.customer_id AS customer_id,
            dcs.customer_name AS customer_name,
            dcs.customer_address AS customer_address,
            dcs.customer_birthday AS customer_birthday,
            dcs.customer_email AS customer_email,
            fo.order_id AS order_id,
            dp.product_id AS product_id,
            dp.product_price AS product_price,
            dp.product_type AS product_type,
            dc.craftsman_id as craftsman_id,
            fo.order_completion_date - fo.order_created_date AS diff_order_date, 
            fo.order_status AS order_status,
            TO_CHAR(fo.order_created_date, 'yyyy-mm') AS report_customer_period,
            crd.customer_id AS exist_customer_id,
            dc.load_dttm AS craftsman_load_dttm,   
            dcs.load_dttm AS customers_load_dttm,
            dp.load_dttm AS products_load_dttm
            FROM dwh.f_order fo 
                INNER JOIN dwh.d_craftsman dc ON fo.craftsman_id = dc.craftsman_id 
                INNER JOIN dwh.d_customer dcs ON fo.customer_id = dcs.customer_id 
                INNER JOIN dwh.d_product dp ON fo.product_id = dp.product_id 
                LEFT JOIN dwh.customer_report_datamart crd ON dcs.customer_id = crd.customer_id
                    WHERE (fo.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_craftsman_report_datamart)) OR
                            (dc.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_craftsman_report_datamart)) OR
                            (dcs.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_craftsman_report_datamart)) OR
                            (dp.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_craftsman_report_datamart))
),

dwh_update_delta AS ( -- делаем выборку покупателей, по которым были изменения в DWH. По этим покупателям данные в витрине нужно будет обновить
    SELECT     
            dd.exist_customer_id AS customer_id
            FROM dwh_customer_delta dd 
                WHERE dd.exist_customer_id IS NOT NULL        
),
 dwh_delta_insert_result AS ( -- делаем расчёт витрины по новым данным. Этой информации по мастерам в рамках расчётного периода раньше не было, это новые данные. Их можно просто вставить (insert) в витрину без обновления
    SELECT  
            T4.customer_id AS customer_id,
            T4.customer_name AS customer_name,
            T4.customer_address AS customer_address,
            T4.customer_birthday AS customer_birthday,
            T4.customer_email AS customer_email,
            T4.customer_money AS customer_money,
            T4.platform_customer_money AS platform_customer_money,
            T4.count_customer_order AS count_customer_order,
            T4.avg_price_customer_order AS avg_price_customer_order,
           	T4.top_product_customer_category as top_product_customer_category,
            t4.top_craftsman_customer as top_craftsman_customer,
            T4.product_type AS top_product_category,
            T4.median_time_customer_order_completed AS median_time_customer_order_completed,
            T4.count_customer_order_created AS count_customer_order_created,
            T4.count_customer_order_in_progress AS count_customer_order_in_progress,
            T4.count_customer_order_delivery AS count_customer_order_delivery,
            T4.count_customer_order_done AS count_customer_order_done,
            T4.count_customer_order_not_done AS count_customer_order_not_done,
            T4.report_customer_period AS report_customer_period 
            FROM (
                SELECT     -- в этой выборке объединяем две внутренние выборки по расчёту столбцов витрины и применяем оконную функцию для определения самой популярной категории товаров
                        *,
                      RANK() OVER(PARTITION BY T2.customer_id ORDER BY count_product DESC) AS top_product_customer_category 
                        FROM ( 
                           		SELECT -- в этой выборке делаем расчёт по большинству столбцов, так как все они требуют одной и той же группировки, кроме столбца с самой популярной категорией товаров у мастера. Для этого столбца сделаем отдельную выборку с другой группировкой и выполним JOIN
                                T1.customer_id AS customer_id,
                                T1.customer_name AS customer_name,
                                T1.customer_address AS customer_address,
                                T1.customer_birthday AS customer_birthday,
                                T1.customer_email AS customer_email,
                                SUM(T1.product_price) customer_money,
                                SUM(T1.product_price) * 0.1 AS platform_customer_money,
                                COUNT(order_id) AS count_customer_order,
                                AVG(T1.product_price) AS avg_price_customer_order,
                                PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY diff_order_date) AS median_time_customer_order_completed,
                                SUM(CASE WHEN T1.order_status = 'created' THEN 1 ELSE 0 END) AS count_customer_order_created,
                                SUM(CASE WHEN T1.order_status = 'in progress' THEN 1 ELSE 0 END) AS count_customer_order_in_progress, 
                                SUM(CASE WHEN T1.order_status = 'delivery' THEN 1 ELSE 0 END) AS count_customer_order_delivery, 
                                SUM(CASE WHEN T1.order_status = 'done' THEN 1 ELSE 0 END) AS count_customer_order_done, 
                                SUM(CASE WHEN T1.order_status != 'done' THEN 1 ELSE 0 END) AS count_customer_order_not_done,
                                T1.report_customer_period AS report_customer_period
                                from dwh_customer_delta AS T1
                                WHERE T1.exist_customer_id IS NULL
                                GROUP BY T1.customer_id, T1.customer_name, T1.customer_address, T1.customer_birthday, T1.customer_email, T1.report_customer_period
                            ) AS T2
                                INNER JOIN (
                                    SELECT dd.customer_id AS customer_id_for_product_type, 
                                            dd.product_type, 
                                            COUNT(dd.product_id) AS count_product
                                            FROM dwh_customer_delta AS dd
                                                GROUP BY dd.customer_id, dd.product_type
                                                    ORDER BY count_product DESC) AS T3 ON T2.customer_id = T3.customer_id_for_product_type
                
                inner join ( select craftsman_id as top_craftsman_customer,top_craftsman_customer_id  from (
                SELECT                                             tt.customer_id AS top_craftsman_customer_id, 
                                            tt.craftsman_id, 
                                            row_number () over (partition by customer_id order by count(*) desc) AS top_craftsman
                                            FROM dwh_customer_delta AS tt
                                                GROUP BY tt.customer_id, tt.craftsman_id
                                                    ORDER by top_craftsman  desc) yy
                                                    where top_craftsman=1
                                                    ) AS T5 ON T2.customer_id = T5.top_craftsman_customer_id)
                                                    
                                                  
                                                    AS T4 WHERE T4.top_product_customer_category = 1  ORDER BY report_customer_period),

 dwh_delta_update_result AS ( -- делаем перерасчёт для существующих записей витринs, так как данные обновились за отчётные периоды. Логика похожа на insert, но нужно достать конкретные данные из DWH
    SELECT 
            T4.customer_id AS customer_id,
            T4.customer_name AS customer_name,
            T4.customer_address AS customer_address,
            T4.customer_birthday AS customer_birthday,
            T4.customer_email AS customer_email,
            T4.customer_money AS customer_money,
            T4.platform_customer_money AS platform_customer_money,
            T4.count_customer_order AS count_customer_order,
            T4.avg_price_customer_order AS avg_price_customer_order,
           	T4.top_product_customer_category as top_product_customer_category,
            t4.top_craftsman_customer as top_craftsman_customer,
            T4.product_type AS top_product_category,
            T4.median_time_customer_order_completed AS median_time_customer_order_completed,
            T4.count_customer_order_created AS count_customer_order_created,
            T4.count_customer_order_in_progress AS count_customer_order_in_progress,
            T4.count_customer_order_delivery AS count_customer_order_delivery,
            T4.count_customer_order_done AS count_customer_order_done,
            T4.count_customer_order_not_done AS count_customer_order_not_done,
            T4.report_customer_period AS report_customer_period 
            FROM (
                SELECT     -- в этой выборке объединяем две внутренние выборки по расчёту столбцов витрины и применяем оконную функцию для определения самой популярной категории товаров
                        *,
                      RANK() OVER(PARTITION BY T2.customer_id ORDER BY count_product DESC) AS top_product_customer_category 
                        FROM (
                            SELECT -- в этой выборке делаем расчёт по большинству столбцов, так как все они требуют одной и той же группировки, кроме столбца с самой популярной категорией товаров у мастера. Для этого столбца сделаем отдельную выборку с другой группировкой и выполним JOIN
                                T1.customer_id AS customer_id,
                                T1.customer_name AS customer_name,
                                T1.customer_address AS customer_address,
                                T1.customer_birthday AS customer_birthday,
                                T1.customer_email AS customer_email,
                                SUM(T1.product_price) customer_money,
                                SUM(T1.product_price) * 0.1 AS platform_customer_money,
                                COUNT(order_id) AS count_customer_order,
                                AVG(T1.product_price) AS avg_price_customer_order,
                                PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY diff_order_date) AS median_time_customer_order_completed,
                                SUM(CASE WHEN T1.order_status = 'created' THEN 1 ELSE 0 END) AS count_customer_order_created,
                                SUM(CASE WHEN T1.order_status = 'in progress' THEN 1 ELSE 0 END) AS count_customer_order_in_progress, 
                                SUM(CASE WHEN T1.order_status = 'delivery' THEN 1 ELSE 0 END) AS count_customer_order_delivery, 
                                SUM(CASE WHEN T1.order_status = 'done' THEN 1 ELSE 0 END) AS count_customer_order_done, 
                                SUM(CASE WHEN T1.order_status != 'done' THEN 1 ELSE 0 END) AS count_customer_order_not_done,
                                T1.report_customer_period AS report_customer_period
                                FROM (
                                    SELECT     -- в этой выборке достаём из DWH обновлённые или новые данные по мастерам, которые уже есть в витрине
                                            dcs.customer_id AS customer_id,
            dcs.customer_name AS customer_name,
            dcs.customer_address AS customer_address,
            dcs.customer_birthday AS customer_birthday,
            dcs.customer_email AS customer_email,
            fo.order_id AS order_id,
            dp.product_id AS product_id,
            dp.product_price AS product_price,
            dp.product_type AS product_type,
            dc.craftsman_id as craftsman_id,
            fo.order_completion_date - fo.order_created_date AS diff_order_date, 
            fo.order_status AS order_status,
            TO_CHAR(fo.order_created_date, 'yyyy-mm') AS report_customer_period
                                           FROM dwh.f_order fo 
                                                INNER JOIN dwh.d_craftsman dc ON fo.craftsman_id = dc.craftsman_id 
                                                INNER JOIN dwh.d_customer dcs ON fo.customer_id = dcs.customer_id 
                                                INNER JOIN dwh.d_product dp ON fo.product_id = dp.product_id
                                                INNER JOIN dwh_update_delta ud ON fo.customer_id = ud.customer_id
                                ) AS T1
                                    GROUP BY T1.customer_id, T1.customer_name, T1.customer_address, T1.customer_birthday, T1.customer_email, T1.report_customer_period
                            ) as T2 INNER JOIN (
                                    SELECT dd.customer_id AS customer_id_for_product_type, 
                                            dd.product_type, 
                                            COUNT(dd.product_id) AS count_product
                                            FROM dwh_customer_delta AS dd
                                                GROUP BY dd.customer_id, dd.product_type
                                                    ORDER BY count_product DESC) AS T3 ON T2.customer_id = T3.customer_id_for_product_type
                
                inner join ( select craftsman_id as top_craftsman_customer,top_craftsman_customer_id  from (
                SELECT                                             tt.customer_id AS top_craftsman_customer_id, 
                                            tt.craftsman_id, 
                                            row_number () over (partition by customer_id order by count(*) desc) AS top_craftsman
                                            FROM dwh_customer_delta AS tt
                                                GROUP BY tt.customer_id, tt.craftsman_id
                                                    ORDER by top_craftsman  desc) yy
                                                    where top_craftsman=1
                                                    ) AS T5 ON T2.customer_id = T5.top_craftsman_customer_id)
                 AS T4 WHERE T4.top_product_customer_category = 1 ORDER BY report_customer_period
),
insert_delta AS ( -- выполняем insert новых расчитанных данных для витрины 
    INSERT INTO dwh.customer_report_datamart (
        	customer_id,
            customer_name,
            customer_address,
            customer_birthday,
            customer_email,
            customer_money,
            platform_customer_money,
            count_customer_order,
            avg_price_customer_order,
           	top_product_customer_category,
            top_craftsman_customer,
            median_time_customer_order_completed,
            count_customer_order_created,
            count_customer_order_in_progress,
            count_customer_order_delivery,
            count_customer_order_done,
            count_customer_order_not_done,
            report_customer_period 
            
    ) SELECT 
            customer_id,
            customer_name,
            customer_address,
            customer_birthday,
            customer_email,
            customer_money,
            platform_customer_money,
            count_customer_order,
            avg_price_customer_order,
           	top_product_customer_category,
            top_craftsman_customer,
            median_time_customer_order_completed,
            count_customer_order_created,
            count_customer_order_in_progress,
            count_customer_order_delivery,
            count_customer_order_done,
            count_customer_order_not_done,
            report_customer_period 
            FROM dwh_delta_insert_result
),
update_delta AS ( -- выполняем обновление показателей в отчёте по уже существующим мастерам
    UPDATE dwh.customer_report_datamart SET
        	customer_id=up.customer_id,
            customer_name=up.customer_name,
            customer_address=up.customer_address,
            customer_birthday=up.customer_birthday,
            customer_email=up.customer_email,
            customer_money=up.customer_money,
            platform_customer_money=up.platform_customer_money,
            count_customer_order=up.count_customer_order,
            avg_price_customer_order=up.avg_price_customer_order,
           	top_product_customer_category=up.top_product_customer_category,
            top_craftsman_customer=up.top_craftsman_customer,
            median_time_customer_order_completed=up.median_time_customer_order_completed,
            count_customer_order_created=up.count_customer_order_created,
            count_customer_order_in_progress=up.count_customer_order_in_progress,
            count_customer_order_delivery=up.count_customer_order_delivery,
            count_customer_order_done=up.count_customer_order_done,
            count_customer_order_not_done=up.count_customer_order_not_done,
            report_customer_period=up.report_customer_period
    FROM (
        SELECT 
            customer_id,
            customer_name,
            customer_address,
            customer_birthday,
            customer_email,
            customer_money,
            platform_customer_money,
            count_customer_order,
            avg_price_customer_order,
           	top_product_customer_category,
            top_craftsman_customer,
            median_time_customer_order_completed,
            count_customer_order_created,
            count_customer_order_in_progress,
            count_customer_order_delivery,
            count_customer_order_done,
            count_customer_order_not_done,
            report_customer_period  
            FROM dwh_delta_update_result) AS up
    WHERE dwh.customer_report_datamart.customer_id = up.customer_id
),
insert_load_date AS ( -- делаем запись в таблицу загрузок о том, когда была совершена загрузка, чтобы в следующий раз взять данные, которые будут добавлены или изменены после этой даты
    INSERT INTO dwh.load_dates_customer_report_datamart (
        load_dttm
    )
    SELECT GREATEST(COALESCE(MAX(craftsman_load_dttm), NOW()), 
                    COALESCE(MAX(customers_load_dttm), NOW()), 
                    COALESCE(MAX(products_load_dttm), NOW())) 
        FROM dwh_customer_delta)
SELECT 'increment datamart'; -- инициализируем запрос CTE
 