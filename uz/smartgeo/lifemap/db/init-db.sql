--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.10
-- Dumped by pg_dump version 9.5.9

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgis; Type: SCHEMA; Schema: -; Owner: lifemap
--

CREATE SCHEMA postgis;


ALTER SCHEMA postgis OWNER TO lifemap;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner:
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner:
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA postgis;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


SET search_path = public, pg_catalog;

--
-- Name: change_user_role_on_update_mobile_phone(); Type: FUNCTION; Schema: public; Owner: lifemap
--

CREATE FUNCTION change_user_role_on_update_mobile_phone() RETURNS trigger
    LANGUAGE plpgsql
AS $$
DECLARE
    DEFAULT_ROLE_ID      integer = 4;
    TRUSTED_USER_ROLE_ID integer = 5;
BEGIN
    IF (TG_OP = 'UPDATE') THEN

        -- if user role equals DEFAULT_ROLE_ID
        IF ((select role_id from lm_user_role where user_id = old.id and old.status = 'A' limit 1) = DEFAULT_ROLE_ID) THEN
            -- if user send contacts, change role to TRUSTED_USER_ROLE
            IF (old.phone_mobile IS NULL and new.phone_mobile IS NOT NULL) THEN

                UPDATE lm_user_role
                SET status   = 'D',
                    exp_date = now()
                WHERE user_id = old.id
                  and role_id = DEFAULT_ROLE_ID
                  and status = 'A';

                INSERT INTO lm_user_role (user_id, role_id) values (NEW.id, TRUSTED_USER_ROLE_ID);
            END IF;
        END IF;

        RETURN NEW;
    END IF;
    RETURN NULL; -- возвращаемое значение для триггера AFTER игнорируется
END;
$$;


ALTER FUNCTION public.change_user_role_on_update_mobile_phone() OWNER TO lifemap;

--
-- Name: create_user_role_on_user_insert(); Type: FUNCTION; Schema: public; Owner: lifemap
--

CREATE FUNCTION create_user_role_on_user_insert() RETURNS trigger
    LANGUAGE plpgsql
AS $$
DECLARE
    DEFAULT_ROLE_ID      integer = 4;
    TRUSTED_USER_ROLE_ID integer = 5;
BEGIN

    -- Create default user role when user created
    IF (TG_OP = 'INSERT') THEN
        IF (new.phone_mobile IS NULL) THEN
            INSERT INTO lm_user_role (user_id, role_id) values (NEW.id, DEFAULT_ROLE_ID);
        ELSEIF (new.phone_mobile IS NOT NULL AND LENGTH(new.phone_mobile) >= 6) THEN
            INSERT INTO lm_user_role (user_id, role_id) values (NEW.id, TRUSTED_USER_ROLE_ID);
        END IF;

        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN

        -- if user role equals DEFAULT_ROLE_ID
        IF ((select role_id from lm_user_role where user_id = old.id and old.status = 'A' limit 1) = DEFAULT_ROLE_ID) THEN
            INSERT INTO lm_user_role (user_id, role_id) values (NEW.id, TRUSTED_USER_ROLE_ID);
            -- if user send contacts, change role to TRUSTED_USER_ROLE
            IF (old.phone_mobile IS NULL and new.phone_mobile IS NOT NULL) THEN

                UPDATE lm_user_role
                SET status   = 'D',
                    exp_date = now()
                WHERE user_id = old.id
                  and role_id = DEFAULT_ROLE_ID
                  and status = 'A';

                INSERT INTO lm_user_role (user_id, role_id) values (NEW.id, TRUSTED_USER_ROLE_ID);
            END IF;
        ELSE
        END IF;

        RETURN NEW;
    END IF;
    RETURN NULL; -- возвращаемое значение для триггера AFTER игнорируется
END;
$$;


ALTER FUNCTION public.create_user_role_on_user_insert() OWNER TO lifemap;

--
-- Name: get_dashboard_data_events(bigint, bigint, bigint, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: lifemap
--

CREATE FUNCTION get_dashboard_data_events(icategory_id bigint, iregion_id bigint, iuser_id bigint, istart_date timestamp without time zone, iend_date timestamp without time zone) RETURNS TABLE(events_count_total integer, events_count_total_telegram integer, events_count_relevant integer, events_count_all integer, events_count_own integer, events_count_moderating integer)
    LANGUAGE plpgsql
AS $$
BEGIN
    -- Возвращает данные по событиям для admin Dashboard
    RETURN QUERY
        -- explain analyse
        select count(e.id) ::integer                    events_count_total,
               count(e.bot_event_id) ::integer          events_count_total_telegram,

               (SELECT count(e_relevant.id)::integer
                from lm_event e_relevant
                         join lm_user u on e_relevant.user_id = u.id and u.status = 'A'
                WHERE e_relevant.status = 'A'
                  and (e_relevant.category_id = icategory_id or icategory_id = 0)
                  and (e_relevant.start_date <= now() and e_relevant.end_date >= now())
                  and (e_relevant.is_moderated = true)) events_count_relevant,

               (SELECT count(e_all.id)::integer
                from lm_event e_all
                WHERE e_all.status = 'A'
                  and (e_all.category_id = icategory_id or icategory_id = 0)
                  and (
                        (e_all.end_date >= istart_date and e_all.end_date <= iend_date) or (e_all.start_date >= istart_date and e_all.end_date <= iend_date) or
                        (e_all.start_date >= istart_date and e_all.start_date <= iend_date) or (e_all.start_date < istart_date and e_all.end_date >= iend_date)
                        or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date
                    )
               )                                        events_count_all,

               (SELECT count(e_own.id)::integer
                from lm_event e_own
                WHERE e_own.status = 'A'
                  and (e_own.user_id = iuser_id or iuser_id = 0)
                  and (e_own.category_id = icategory_id or icategory_id = 0)
               )                                        events_count_own,
               (SELECT count(e_moderating.id)::integer
                from lm_event e_moderating
                WHERE e_moderating.status = 'A'
                  and (e_moderating.user_id = iuser_id or iuser_id = 0)
                  and (e_moderating.category_id = icategory_id or icategory_id = 0)
                  and (is_moderated is null)
                  and (
                        (e_moderating.end_date >= istart_date and e_moderating.end_date <= iend_date) or
                        (e_moderating.start_date >= istart_date and e_moderating.end_date <= iend_date) or
                        (e_moderating.start_date >= istart_date and e_moderating.start_date <= iend_date) or
                        (e_moderating.start_date < istart_date and e_moderating.end_date >= iend_date)
                        or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date
                    )
               )                                        events_count_moderating

        from lm_event e

        where status = 'A';

END;
$$;


ALTER FUNCTION public.get_dashboard_data_events(icategory_id bigint, iregion_id bigint, iuser_id bigint, istart_date timestamp without time zone, iend_date timestamp without time zone) OWNER TO lifemap;

--
-- Name: get_dashboard_data_events_by_category_filter(timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: lifemap
--

CREATE FUNCTION get_dashboard_data_events_by_category_filter(istart_date timestamp without time zone, iend_date timestamp without time zone) RETURNS TABLE(category_id bigint, category_name text, relevant_events_count integer, all_events_count integer, moderating_events_count integer)
    LANGUAGE plpgsql
AS $$
BEGIN
    -- Возвращает данные по количеству событий в разрезе категорий событий
    RETURN QUERY
        -- explain analyse
        select ctgr.id                                  category_id,
               ctgr.name                                category_name,
               (SELECT count(e_relevant.id)::integer
                from lm_event e_relevant
                         join lm_user u on e_relevant.user_id = u.id and u.status = 'A'
                WHERE e_relevant.status = 'A'
                  and (e_relevant.category_id = ctgr.id or ctgr.id = 0)
                  and (e_relevant.start_date <= now() and e_relevant.end_date >= now())
                  and (e_relevant.is_moderated = true)) relevant_events_count,

               (SELECT count(e_all.id)::integer
                from lm_event e_all
                WHERE e_all.status = 'A'
                  and (e_all.category_id = ctgr.id or ctgr.id = 0)
                  and ((e_all.end_date >= istart_date and e_all.end_date <= iend_date) or (e_all.start_date >= istart_date and e_all.end_date <= iend_date) or
                       (e_all.start_date >= istart_date and e_all.start_date <= iend_date) or (e_all.start_date < istart_date and e_all.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
               )                                        all_events_count,

               (SELECT count(e_moderating.id)::integer
                from lm_event e_moderating
                WHERE e_moderating.status = 'A'
                  and (e_moderating.category_id = ctgr.id or ctgr.id = 0)
                  and (is_moderated is null)
                  and (
                        (e_moderating.end_date >= istart_date and e_moderating.end_date <= iend_date) or
                        (e_moderating.start_date >= istart_date and e_moderating.end_date <= iend_date) or
                        (e_moderating.start_date >= istart_date and e_moderating.start_date <= iend_date) or
                        (e_moderating.start_date < istart_date and e_moderating.end_date >= iend_date)
                        or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date
                    )
               )                                        moderating_events_count

        from lm_event_category ctgr
        where ctgr.status = 'A'
        order by id;

END;
$$;


ALTER FUNCTION public.get_dashboard_data_events_by_category_filter(istart_date timestamp without time zone, iend_date timestamp without time zone) OWNER TO lifemap;

--
-- Name: get_dashboard_data_events_by_category_region(timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: lifemap
--

CREATE FUNCTION get_dashboard_data_events_by_category_region(istart_date timestamp without time zone, iend_date timestamp without time zone) RETURNS TABLE(category_id bigint, category_name text, unknown_region_events_count integer, tashkent_events_count integer, andijan_region_events_count integer, bukhara_region_events_count integer, jizzakh_region_events_count integer, qashqadaryo_region_events_count integer, navoiy_region_events_count integer, namangan_region_events_count integer, samarqand_region_events_count integer, surxondaryo_region_events_count integer, sirdaryo_region_events_count integer, tashkent_region_events_count integer, fergana_region_events_count integer, xorazm_region_events_count integer, karakalpakstan_events_count integer)
    LANGUAGE plpgsql
AS $$
DECLARE
    REGION_UNKNOWN        integer = 1;
    REGION_TASHKENT       integer = 2;
    REGION_ANDIJAN        integer = 3;
    REGION_BUKHARA        integer = 4;
    REGION_JIZZAKH        integer = 5;
    REGION_QASHQADARYO    integer = 6;
    REGION_NAVOIY         integer = 7;
    REGION_NAMANGAN       integer = 8;
    REGION_SAMARKAND      integer = 9;
    REGION_SURHONDARYO    integer = 10;
    REGION_SIRDARYO       integer = 11;
    REGION_TAHKENT        integer = 12;
    REGION_FERGANA        integer = 13;
    REGION_XORAZM         integer = 14;
    REGION_KARAKALPAKSTAN integer = 15;

BEGIN
    -- Возвращает данные по количеству событий в разрезе категорий событий и регионов
    RETURN QUERY
        -- explain analyse
        select ctgr.id                                                                  category_id,
               ctgr.name                                                                category_name,

               (SELECT count(unknown_region_events.id)::integer
                from lm_event unknown_region_events
                WHERE unknown_region_events.status = 'A'
                  and (unknown_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((unknown_region_events.end_date >= istart_date and unknown_region_events.end_date <= iend_date) or
                       (unknown_region_events.start_date >= istart_date and unknown_region_events.end_date <= iend_date) or
                       (unknown_region_events.start_date >= istart_date and unknown_region_events.start_date <= iend_date) or
                       (unknown_region_events.start_date < istart_date and unknown_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (unknown_region_events.region_id = REGION_UNKNOWN))               unknown_region_events,

               (SELECT count(tashkent_events.id)::integer
                from lm_event tashkent_events
                WHERE tashkent_events.status = 'A'
                  and (tashkent_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((tashkent_events.end_date >= istart_date and tashkent_events.end_date <= iend_date) or
                       (tashkent_events.start_date >= istart_date and tashkent_events.end_date <= iend_date) or
                       (tashkent_events.start_date >= istart_date and tashkent_events.start_date <= iend_date) or
                       (tashkent_events.start_date < istart_date and tashkent_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (tashkent_events.region_id = REGION_TASHKENT))                    tashkent_events,

               (SELECT count(andijan_region_events.id)::integer
                from lm_event andijan_region_events
                WHERE andijan_region_events.status = 'A'
                  and (andijan_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((andijan_region_events.end_date >= istart_date and andijan_region_events.end_date <= iend_date) or
                       (andijan_region_events.start_date >= istart_date and andijan_region_events.end_date <= iend_date) or
                       (andijan_region_events.start_date >= istart_date and andijan_region_events.start_date <= iend_date) or
                       (andijan_region_events.start_date < istart_date and andijan_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (andijan_region_events.region_id = REGION_ANDIJAN))               andijan_region_events,

               (SELECT count(bukhara_region_events.id)::integer
                from lm_event bukhara_region_events
                WHERE bukhara_region_events.status = 'A'
                  and (bukhara_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((bukhara_region_events.end_date >= istart_date and bukhara_region_events.end_date <= iend_date) or
                       (bukhara_region_events.start_date >= istart_date and bukhara_region_events.end_date <= iend_date) or
                       (bukhara_region_events.start_date >= istart_date and bukhara_region_events.start_date <= iend_date) or
                       (bukhara_region_events.start_date < istart_date and bukhara_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (bukhara_region_events.region_id = REGION_BUKHARA))               bukhara_region_events,

               (SELECT count(jizzakh_region_events.id)::integer
                from lm_event jizzakh_region_events
                WHERE jizzakh_region_events.status = 'A'
                  and (jizzakh_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((jizzakh_region_events.end_date >= istart_date and jizzakh_region_events.end_date <= iend_date) or
                       (jizzakh_region_events.start_date >= istart_date and jizzakh_region_events.end_date <= iend_date) or
                       (jizzakh_region_events.start_date >= istart_date and jizzakh_region_events.start_date <= iend_date) or
                       (jizzakh_region_events.start_date < istart_date and jizzakh_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (jizzakh_region_events.region_id = REGION_JIZZAKH))               jizzakh_region_events,

               (SELECT count(qashqadaryo_region_events.id)::integer
                from lm_event qashqadaryo_region_events
                WHERE qashqadaryo_region_events.status = 'A'
                  and (qashqadaryo_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((qashqadaryo_region_events.end_date >= istart_date and qashqadaryo_region_events.end_date <= iend_date) or
                       (qashqadaryo_region_events.start_date >= istart_date and qashqadaryo_region_events.end_date <= iend_date) or
                       (qashqadaryo_region_events.start_date >= istart_date and qashqadaryo_region_events.start_date <= iend_date) or
                       (qashqadaryo_region_events.start_date < istart_date and qashqadaryo_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (qashqadaryo_region_events.region_id = REGION_QASHQADARYO))       qashqadaryo_region_events,

               (SELECT count(navoiy_region_events.id)::integer
                from lm_event navoiy_region_events
                WHERE navoiy_region_events.status = 'A'
                  and (navoiy_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((navoiy_region_events.end_date >= istart_date and navoiy_region_events.end_date <= iend_date) or
                       (navoiy_region_events.start_date >= istart_date and navoiy_region_events.end_date <= iend_date) or
                       (navoiy_region_events.start_date >= istart_date and navoiy_region_events.start_date <= iend_date) or
                       (navoiy_region_events.start_date < istart_date and navoiy_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (navoiy_region_events.region_id = REGION_NAVOIY))                 navoiy_region_events,

               (SELECT count(namangan_region_events.id)::integer
                from lm_event namangan_region_events
                WHERE namangan_region_events.status = 'A'
                  and (namangan_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((namangan_region_events.end_date >= istart_date and namangan_region_events.end_date <= iend_date) or
                       (namangan_region_events.start_date >= istart_date and namangan_region_events.end_date <= iend_date) or
                       (namangan_region_events.start_date >= istart_date and namangan_region_events.start_date <= iend_date) or
                       (namangan_region_events.start_date < istart_date and namangan_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (namangan_region_events.region_id = REGION_NAMANGAN))             namangan_region_events,

               (SELECT count(samarqand_region_events.id)::integer
                from lm_event samarqand_region_events
                WHERE samarqand_region_events.status = 'A'
                  and (samarqand_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((samarqand_region_events.end_date >= istart_date and samarqand_region_events.end_date <= iend_date) or
                       (samarqand_region_events.start_date >= istart_date and samarqand_region_events.end_date <= iend_date) or
                       (samarqand_region_events.start_date >= istart_date and samarqand_region_events.start_date <= iend_date) or
                       (samarqand_region_events.start_date < istart_date and samarqand_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (samarqand_region_events.region_id = REGION_SAMARKAND))           samarqand_region_events,

               (SELECT count(surxondaryo_region_events.id)::integer
                from lm_event surxondaryo_region_events
                WHERE surxondaryo_region_events.status = 'A'
                  and (surxondaryo_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((surxondaryo_region_events.end_date >= istart_date and surxondaryo_region_events.end_date <= iend_date) or
                       (surxondaryo_region_events.start_date >= istart_date and surxondaryo_region_events.end_date <= iend_date) or
                       (surxondaryo_region_events.start_date >= istart_date and surxondaryo_region_events.start_date <= iend_date) or
                       (surxondaryo_region_events.start_date < istart_date and surxondaryo_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (surxondaryo_region_events.region_id = REGION_SURHONDARYO))       surxondaryo_region_events,

               (SELECT count(sirdaryo_region_events.id)::integer
                from lm_event sirdaryo_region_events
                WHERE sirdaryo_region_events.status = 'A'
                  and (sirdaryo_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((sirdaryo_region_events.end_date >= istart_date and sirdaryo_region_events.end_date <= iend_date) or
                       (sirdaryo_region_events.start_date >= istart_date and sirdaryo_region_events.end_date <= iend_date) or
                       (sirdaryo_region_events.start_date >= istart_date and sirdaryo_region_events.start_date <= iend_date) or
                       (sirdaryo_region_events.start_date < istart_date and sirdaryo_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (sirdaryo_region_events.region_id = REGION_SIRDARYO))             sirdaryo_region_events,

               (SELECT count(tashkent_region_events.id)::integer
                from lm_event tashkent_region_events
                WHERE tashkent_region_events.status = 'A'
                  and (tashkent_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((tashkent_region_events.end_date >= istart_date and tashkent_region_events.end_date <= iend_date) or
                       (tashkent_region_events.start_date >= istart_date and tashkent_region_events.end_date <= iend_date) or
                       (tashkent_region_events.start_date >= istart_date and tashkent_region_events.start_date <= iend_date) or
                       (tashkent_region_events.start_date < istart_date and tashkent_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (tashkent_region_events.region_id = REGION_TAHKENT))              tashkent_region_events,

               (SELECT count(fergana_region_events.id)::integer
                from lm_event fergana_region_events
                WHERE fergana_region_events.status = 'A'
                  and (fergana_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((fergana_region_events.end_date >= istart_date and fergana_region_events.end_date <= iend_date) or
                       (fergana_region_events.start_date >= istart_date and fergana_region_events.end_date <= iend_date) or
                       (fergana_region_events.start_date >= istart_date and fergana_region_events.start_date <= iend_date) or
                       (fergana_region_events.start_date < istart_date and fergana_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (fergana_region_events.region_id = REGION_FERGANA))               fergana_region_events,

               (SELECT count(xorazm_region_events.id)::integer
                from lm_event xorazm_region_events
                WHERE xorazm_region_events.status = 'A'
                  and (xorazm_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((xorazm_region_events.end_date >= istart_date and xorazm_region_events.end_date <= iend_date) or
                       (xorazm_region_events.start_date >= istart_date and xorazm_region_events.end_date <= iend_date) or
                       (xorazm_region_events.start_date >= istart_date and xorazm_region_events.start_date <= iend_date) or
                       (xorazm_region_events.start_date < istart_date and xorazm_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (xorazm_region_events.region_id = REGION_XORAZM))                 xorazm_region_events,

               (SELECT count(karakalpakstan_region_events.id)::integer
                from lm_event karakalpakstan_region_events
                WHERE karakalpakstan_region_events.status = 'A'
                  and (karakalpakstan_region_events.category_id = ctgr.id or ctgr.id = 0)
                  and ((karakalpakstan_region_events.end_date >= istart_date and karakalpakstan_region_events.end_date <= iend_date) or
                       (karakalpakstan_region_events.start_date >= istart_date and karakalpakstan_region_events.end_date <= iend_date) or
                       (karakalpakstan_region_events.start_date >= istart_date and karakalpakstan_region_events.start_date <= iend_date) or
                       (karakalpakstan_region_events.start_date < istart_date and karakalpakstan_region_events.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
                  and (karakalpakstan_region_events.region_id = REGION_KARAKALPAKSTAN)) karakalpakstan_region_events

        from lm_event_category ctgr
        where ctgr.status = 'A'
        order by id;

END;
$$;


ALTER FUNCTION public.get_dashboard_data_events_by_category_region(istart_date timestamp without time zone, iend_date timestamp without time zone) OWNER TO lifemap;

--
-- Name: get_dashboard_data_events_by_region_filter(timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: lifemap
--

CREATE FUNCTION get_dashboard_data_events_by_region_filter(istart_date timestamp without time zone, iend_date timestamp without time zone) RETURNS TABLE(region_id bigint, region_name_en text, relevant_events_count integer, all_events_count integer, moderating_events_count integer)
    LANGUAGE plpgsql
AS $$
BEGIN
    -- Возвращает данные по количеству событий в разрезе регионов
    RETURN QUERY
        -- explain analyse
        select rg.id                                    region_id,
               rg.name_en                               region_name_en,
               (SELECT count(e_relevant.id)::integer
                from lm_event e_relevant
                         join lm_user u on e_relevant.user_id = u.id and u.status = 'A'
                WHERE e_relevant.status = 'A'
                  and (e_relevant.region_id = rg.id)
                  and (e_relevant.start_date <= now() and e_relevant.end_date >= now())
                  and (e_relevant.is_moderated = true)) relevant_events_count,

               (SELECT count(e_all.id)::integer
                from lm_event e_all
                WHERE e_all.status = 'A'
                  and (e_all.region_id = rg.id or rg.id = 0)
                  and ((e_all.end_date >= istart_date and e_all.end_date <= iend_date) or (e_all.start_date >= istart_date and e_all.end_date <= iend_date) or
                       (e_all.start_date >= istart_date and e_all.start_date <= iend_date) or (e_all.start_date < istart_date and e_all.end_date >= iend_date)
                    or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date)
               )                                        all_events_count,

               (SELECT count(e_moderating.id)::integer
                from lm_event e_moderating
                WHERE e_moderating.status = 'A'
                  and (e_moderating.region_id = rg.id)
                  and (is_moderated is null)
                  and (
                        (e_moderating.end_date >= istart_date and e_moderating.end_date <= iend_date) or
                        (e_moderating.start_date >= istart_date and e_moderating.end_date <= iend_date) or
                        (e_moderating.start_date >= istart_date and e_moderating.start_date <= iend_date) or
                        (e_moderating.start_date < istart_date and e_moderating.end_date >= iend_date)
                        or CAST('1970-01-01' AS timestamp) = istart_date or CAST('1970-01-01' AS timestamp) = iend_date
                    )
               )                                        moderating_events_count

        from lm_region rg
        where rg.status = 'A'
        order by id;

END;
$$;


ALTER FUNCTION public.get_dashboard_data_events_by_region_filter(istart_date timestamp without time zone, iend_date timestamp without time zone) OWNER TO lifemap;

--
-- Name: get_dashboard_data_users(); Type: FUNCTION; Schema: public; Owner: lifemap
--

CREATE FUNCTION get_dashboard_data_users() RETURNS TABLE(users_count_total integer, users_count_role_admin integer, users_count_role_moderator integer, users_count_role_user integer, users_count_role_trusted_user integer)
    LANGUAGE plpgsql
AS $$
DECLARE
    ROLE_ROOT         BIGINT = 1;
    ROLE_ADMIN        BIGINT = 2;
    ROLE_MODERATOR    BIGINT = 3;
    ROLE_USER         BIGINT = 4;
    ROLE_TRUSTED_USER BIGINT = 5;
BEGIN


    -- Возвращает данные по пользователям для admin Dashboard
    RETURN QUERY
        -- explain analyse
        select count(u.id)::integer users_count_total,

               (SELECT count(u_admin.id)::integer
                from lm_user u_admin
                         join lm_user_role ur on u_admin.id = ur.user_id and ur.status = 'A'
                WHERE u_admin.status = 'A'
                  and ur.role_id = ROLE_ADMIN
               )                    users_count_role_admin,
               (SELECT count(u_admin.id)::integer
                from lm_user u_admin
                         join lm_user_role ur on u_admin.id = ur.user_id and ur.status = 'A'
                WHERE u_admin.status = 'A'
                  and ur.role_id = ROLE_MODERATOR
               )                    users_count_role_moderator,
               (SELECT count(u_admin.id)::integer
                from lm_user u_admin
                         join lm_user_role ur on u_admin.id = ur.user_id and ur.status = 'A'
                WHERE u_admin.status = 'A'
                  and ur.role_id = ROLE_USER
               )                    users_count_role_user,
               (SELECT count(u_admin.id)::integer
                from lm_user u_admin
                         join lm_user_role ur on u_admin.id = ur.user_id and ur.status = 'A'
                WHERE u_admin.status = 'A'
                  and ur.role_id = ROLE_TRUSTED_USER
               )                    users_count_role_trusted_user

        from lm_user u
                 join lm_user_role ur on u.id = ur.user_id and ur.status = 'A'

        where u.status = 'A'
          and ur.role_id != ROLE_ROOT;

END;
$$;


ALTER FUNCTION public.get_dashboard_data_users() OWNER TO lifemap;

--
-- Name: get_region_by_location(double precision, double precision); Type: FUNCTION; Schema: public; Owner: lifemap
--

CREATE FUNCTION get_region_by_location(ilongitude double precision, ilatitude double precision) RETURNS bigint
    LANGUAGE plpgsql
AS $$

DECLARE
    p_region     RECORD;
    is_in_region boolean;
BEGIN
    FOR p_region IN
        select rg.id, rg.name_en, rg.geom
        from lm_region rg
        where geom is not null
          and country_id = 2
          and status = 'A'
        LOOP
            raise INFO 'rg id: %', p_region.id;
            raise INFO 'rg name: %', p_region.name_en;

            select postgis.ST_Within(
                           postgis.ST_GeomFromText('POINT(' || ilongitude || ' ' || ilatitude || ')'),
                           p_region.geom)
            into is_in_region;

            raise INFO 'is_in_region: %', is_in_region;

            if is_in_region = true then
                RETURN p_region.id ;
            else
                raise INFO 'check next region with coordinates';

            end if;

        END LOOP;
    RETURN 0;

END;
$$;


ALTER FUNCTION public.get_region_by_location(ilongitude double precision, ilatitude double precision) OWNER TO lifemap;

--
-- Name: save_event_action(); Type: FUNCTION; Schema: public; Owner: lifemap
--

CREATE FUNCTION save_event_action() RETURNS trigger
    LANGUAGE plpgsql
AS $$
DECLARE
    UPDATE_EVENT_USER         bigint = 1;
    UPDATE_EVENT_CATEGORY     bigint = 2;
    UPDATE_EVENT_ADDRESS      bigint = 3;
    UPDATE_EVENT_GEOJSON      bigint = 4;
    UPDATE_EVENT_NAME         bigint = 5;
    UPDATE_EVENT_DESCRIPTION  bigint = 6;
    UPDATE_EVENT_START_DATE   bigint = 7;
    UPDATE_EVENT_END_DATE     bigint = 8;
    UPDATE_EVENT_IS_MODERATED bigint = 9;

BEGIN
    IF (TG_OP = 'UPDATE') THEN

        IF (new.action_user_id is null) THEN
            RETURN NEW;
        END IF;

        -- update event user
        IF (old.user_id != new.user_id) THEN
            INSERT INTO lm_event_action (event_id, user_id, previous_value, current_value, action_type_id)
            values (NEW.id, NEW.action_user_id, old.user_id, NEW.user_id, UPDATE_EVENT_USER);
        END IF;

        -- update event category
        IF (old.category_id != new.category_id) THEN
            INSERT INTO lm_event_action (event_id, user_id, previous_value, current_value, action_type_id)
            values (NEW.id, NEW.action_user_id, old.category_id, NEW.category_id, UPDATE_EVENT_CATEGORY);
        END IF;

        -- update event address
        IF (old.address != new.address) THEN
            INSERT INTO lm_event_action (event_id, user_id, previous_value, current_value, action_type_id)
            values (NEW.id, NEW.action_user_id, old.address, NEW.address, UPDATE_EVENT_ADDRESS);
        END IF;

        -- update event geojson
        IF (old.geojson::json::text != new.geojson::json::text) THEN
            INSERT INTO lm_event_action (event_id, user_id, previous_value, current_value, action_type_id)
            values (NEW.id, NEW.action_user_id, old.geojson, NEW.geojson, UPDATE_EVENT_GEOJSON);
        END IF;

        -- update event name
        IF (old.name != new.name) THEN
            INSERT INTO lm_event_action (event_id, user_id, previous_value, current_value, action_type_id)
            values (NEW.id, NEW.action_user_id, old.name, NEW.name, UPDATE_EVENT_NAME);
        END IF;

        -- update event description
        IF (old.description != new.description or old.description is null and new.description is not null) THEN
            INSERT INTO lm_event_action (event_id, user_id, previous_value, current_value, action_type_id)
            values (NEW.id, NEW.action_user_id, old.description, NEW.description, UPDATE_EVENT_DESCRIPTION);
        END IF;

        -- update event start date
        IF (old.start_date != new.start_date) THEN
            INSERT INTO lm_event_action (event_id, user_id, previous_value, current_value, action_type_id)
            values (NEW.id, NEW.action_user_id, old.start_date, NEW.start_date, UPDATE_EVENT_START_DATE);
        END IF;

        -- update event end date
        IF (old.end_date != new.end_date) THEN
            INSERT INTO lm_event_action (event_id, user_id, previous_value, current_value, action_type_id)
            values (NEW.id, NEW.action_user_id, old.end_date, NEW.end_date, UPDATE_EVENT_END_DATE);
        END IF;

        -- update event is moderated
        IF ((old.is_moderated != new.is_moderated) or (old.is_moderated is null and new.is_moderated is not null)) THEN
            INSERT INTO lm_event_action (event_id, user_id, previous_value, current_value, action_type_id)
            values (NEW.id, NEW.action_user_id, old.is_moderated, NEW.is_moderated, UPDATE_EVENT_IS_MODERATED);
        END IF;

        RETURN NEW;

    END IF;
    RETURN NULL; -- возвращаемое значение для триггера AFTER игнорируется
END;
$$;


ALTER FUNCTION public.save_event_action() OWNER TO lifemap;

--
-- Name: to_time_tashkent(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION to_time_tashkent(datetime timestamp with time zone) RETURNS timestamp without time zone
    LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN dateTime AT TIME ZONE 'Asia/Tashkent';
END;
$$;


ALTER FUNCTION public.to_time_tashkent(datetime timestamp with time zone) OWNER TO postgres;

--
-- Name: to_time_utc(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION to_time_utc(datetime timestamp with time zone) RETURNS timestamp without time zone
    LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN dateTime AT TIME ZONE 'UTC';
END;
$$;


ALTER FUNCTION public.to_time_utc(datetime timestamp with time zone) OWNER TO postgres;

--
-- Name: to_time_zone(timestamp without time zone, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION to_time_zone(datetime timestamp without time zone, timezone text) RETURNS timestamp without time zone
    LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN dateTime AT TIME ZONE timeZone;
END;
$$;


ALTER FUNCTION public.to_time_zone(datetime timestamp without time zone, timezone text) OWNER TO postgres;

--
-- Name: to_time_zone(timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: lifemap
--

CREATE FUNCTION to_time_zone(datetime timestamp with time zone, timezone text) RETURNS timestamp without time zone
    LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN dateTime AT TIME ZONE timeZone;
END;
$$;


ALTER FUNCTION public.to_time_zone(datetime timestamp with time zone, timezone text) OWNER TO lifemap;

--
-- Name: user_get_and_update(bigint, integer); Type: FUNCTION; Schema: public; Owner: uzgps
--

CREATE FUNCTION user_get_and_update(iext_user_id bigint, iauth_type integer) RETURNS TABLE(id bigint, role_id bigint, ext_user_id bigint, login text, first_name text, last_name text, auth_type_id integer, photo_url text, phone_mobile text, is_blocked boolean, region_id bigint)
    LANGUAGE plpgsql
AS $$
DECLARE
    p_current_date_block TIMESTAMP WITHOUT TIME ZONE;
--     p_user               lm_user;
    AUTH_TYPE_TELEGRAM   BIGINT = 1;
BEGIN
    /**
    Updated 18.05.2020
   */
    p_current_date_block = date_trunc('day', now());

    CREATE TEMPORARY TABLE IF NOT EXISTS p_user
    (
        p_id           bigint,
        p_role_id      bigint,
        p_ext_user_id  bigint,
        p_login        text,
        p_first_name   text,
        p_last_name    text,
        p_auth_type_id integer,
        p_photo_url    text,
        p_phone_mobile text,
        p_is_blocked   boolean,
        p_region_id    bigint
    );

    -- Get user by ext_user_id
    insert into p_user
    SELECT guser.id,
           ur.role_id,
           guser.ext_user_id,
           guser.login,
           guser.first_name,
           guser.last_name,
           guser.auth_type_id,
           guser.photo_url,
           guser.phone_mobile,
           guser.is_blocked,
           guser.region_id
    FROM lm_user guser
             inner join lm_user_role ur on guser.id = ur.user_id and ur.status = 'A'
    WHERE guser.ext_user_id = iext_user_id
      AND guser.auth_type_id = iauth_type
    limit 1;

    if found then
        update lm_user u_user
        set last_logged_in = now(),
            mod_date       = now()
        WHERE u_user.ext_user_id = iext_user_id
          AND u_user.auth_type_id = iauth_type;
    else
    end if;

    return query select * from p_user;
    drop table if exists p_user;
END

$$;


ALTER FUNCTION public.user_get_and_update(iext_user_id bigint, iauth_type integer) OWNER TO uzgps;

--
-- Name: user_get_or_create(bigint, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION user_get_or_create(iext_user_id bigint, iauth_type integer) RETURNS TABLE(id bigint)
    LANGUAGE plpgsql
AS $$
DECLARE
    p_current_date_block     TIMESTAMP WITHOUT TIME ZONE;
    AUTH_TYPE_TELEGRAM       BIGINT = 1;
BEGIN
    /**
    Updated 09.04.2020
   */
    p_current_date_block = date_trunc('day', now());

    CREATE TEMPORARY TABLE IF NOT EXISTS updated_gps_units
    (
        u_id bigint
    );

    -- Get user by ext_user_id
    SELECT ext_user_id, login, first_name, last_name, auth_type_id, photo_url
    FROM lm_user
    WHERE lm_user.ext_user_id = iext_user_id
      AND auth_type_id = iauth_type
    limit 1;

    if found then

    else

    end if;

    return query select * from iext_user_id;


END

$$;


ALTER FUNCTION public.user_get_or_create(iext_user_id bigint, iauth_type integer) OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: lm_auth_type; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_auth_type (
                              id bigint NOT NULL,
                              name text NOT NULL,
                              description text,
                              status character(1) DEFAULT 'A'::bpchar,
                              reg_date timestamp without time zone DEFAULT now(),
                              mod_date timestamp without time zone,
                              exp_date timestamp without time zone
);


ALTER TABLE lm_auth_type OWNER TO lifemap;

--
-- Name: lm_auth_type_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_auth_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_auth_type_id_seq OWNER TO lifemap;

--
-- Name: lm_auth_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_auth_type_id_seq OWNED BY lm_auth_type.id;


--
-- Name: lm_bot_event; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_bot_event (
                              id bigint NOT NULL,
                              user_id bigint NOT NULL,
                              ext_user_id bigint NOT NULL,
                              category_id bigint,
                              name text,
                              description text,
                              start_date timestamp with time zone,
                              end_date timestamp with time zone,
                              country_code text,
                              region text,
                              address text,
                              geojson json,
                              complete_date timestamp without time zone,
                              is_imported boolean,
                              imported_date timestamp without time zone,
                              status character(1) DEFAULT 'A'::bpchar,
                              reg_date timestamp without time zone DEFAULT now(),
                              mod_date timestamp without time zone,
                              exp_date timestamp without time zone
);


ALTER TABLE lm_bot_event OWNER TO lifemap;

--
-- Name: lm_bot_event_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_bot_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_bot_event_id_seq OWNER TO lifemap;

--
-- Name: lm_bot_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_bot_event_id_seq OWNED BY lm_bot_event.id;


--
-- Name: lm_bot_user_option; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_bot_user_option (
                                    user_id bigint NOT NULL,
                                    lang text,
                                    is_start_text_shown boolean DEFAULT false,
                                    status character(1) DEFAULT 'A'::bpchar,
                                    reg_date timestamp without time zone DEFAULT now(),
                                    mod_date timestamp without time zone,
                                    exp_date timestamp without time zone
);


ALTER TABLE lm_bot_user_option OWNER TO lifemap;

--
-- Name: lm_bot_user_state; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_bot_user_state (
                                   user_id bigint,
                                   chat_id bigint,
                                   state integer DEFAULT 0 NOT NULL,
                                   lang text DEFAULT 'en'::text,
                                   status character(1) DEFAULT 'A'::bpchar,
                                   reg_date timestamp without time zone DEFAULT now(),
                                   mod_date timestamp without time zone,
                                   exp_date timestamp without time zone
);


ALTER TABLE lm_bot_user_state OWNER TO lifemap;

--
-- Name: lm_country; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_country (
                            id bigint NOT NULL,
                            name text NOT NULL,
                            name_en text,
                            name_ru text,
                            name_uz text,
                            description text,
                            status character(1) DEFAULT 'A'::bpchar,
                            reg_date timestamp without time zone DEFAULT now(),
                            mod_date timestamp without time zone,
                            exp_date timestamp without time zone
);


ALTER TABLE lm_country OWNER TO lifemap;

--
-- Name: lm_country_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_country_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_country_id_seq OWNER TO lifemap;

--
-- Name: lm_country_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_country_id_seq OWNED BY lm_country.id;


--
-- Name: lm_event; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_event (
                          id bigint NOT NULL,
                          user_id bigint NOT NULL,
                          category_id bigint NOT NULL,
                          name text,
                          address text,
                          start_date timestamp with time zone,
                          end_date timestamp with time zone,
                          description text,
                          geometry_type text DEFAULT 'point'::text,
                          is_active boolean DEFAULT true,
                          geojson json,
                          country_code text,
                          status character(1) DEFAULT 'A'::bpchar,
                          reg_date timestamp without time zone DEFAULT now(),
                          mod_date timestamp without time zone,
                          exp_date timestamp without time zone,
                          is_moderated boolean,
                          duration_min bigint DEFAULT 1440 NOT NULL,
                          perform_deletion_user_id bigint,
                          show_name_for_anonym boolean DEFAULT true,
                          show_description_for_anonym boolean DEFAULT false,
                          action_user_id bigint,
                          bot_event_id bigint,
                          region text,
                          region_id bigint DEFAULT 1
);


ALTER TABLE lm_event OWNER TO lifemap;

--
-- Name: lm_event_action; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_event_action (
                                 id bigint NOT NULL,
                                 event_id bigint NOT NULL,
                                 user_id bigint NOT NULL,
                                 action_type_id bigint NOT NULL,
                                 previous_value text,
                                 current_value text,
                                 details text,
                                 status character(1) DEFAULT 'A'::bpchar,
                                 reg_date timestamp without time zone DEFAULT now(),
                                 mod_date timestamp without time zone,
                                 exp_date timestamp without time zone
);


ALTER TABLE lm_event_action OWNER TO lifemap;

--
-- Name: lm_event_action_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_event_action_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_event_action_id_seq OWNER TO lifemap;

--
-- Name: lm_event_action_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_event_action_id_seq OWNED BY lm_event_action.id;


--
-- Name: lm_event_action_type; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_event_action_type (
                                      id bigint NOT NULL,
                                      name text,
                                      description text,
                                      status character(1) DEFAULT 'A'::bpchar,
                                      reg_date timestamp without time zone DEFAULT now(),
                                      mod_date timestamp without time zone,
                                      exp_date timestamp without time zone
);


ALTER TABLE lm_event_action_type OWNER TO lifemap;

--
-- Name: lm_event_action_type_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_event_action_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_event_action_type_id_seq OWNER TO lifemap;

--
-- Name: lm_event_action_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_event_action_type_id_seq OWNED BY lm_event_action_type.id;


--
-- Name: lm_event_category; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_event_category (
                                   id bigint NOT NULL,
                                   name text NOT NULL,
                                   description text,
                                   help_type_id bigint DEFAULT 1,
                                   pin_url text,
                                   is_active boolean DEFAULT true,
                                   status character(1) DEFAULT 'A'::bpchar,
                                   reg_date timestamp without time zone DEFAULT now(),
                                   mod_date timestamp without time zone,
                                   exp_date timestamp without time zone,
                                   is_visible boolean DEFAULT true,
                                   duration_min bigint DEFAULT 1440
);


ALTER TABLE lm_event_category OWNER TO lifemap;

--
-- Name: lm_event_category_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_event_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_event_category_id_seq OWNER TO lifemap;

--
-- Name: lm_event_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_event_category_id_seq OWNED BY lm_event_category.id;


--
-- Name: lm_event_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_event_id_seq OWNER TO lifemap;

--
-- Name: lm_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_event_id_seq OWNED BY lm_event.id;


--
-- Name: lm_event_response; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_event_response (
                                   id bigint NOT NULL,
                                   event_id bigint,
                                   responsed_user_id bigint NOT NULL,
                                   name text,
                                   message text,
                                   start_date timestamp with time zone,
                                   end_date timestamp with time zone,
                                   is_completed boolean DEFAULT false,
                                   status character(1) DEFAULT 'A'::bpchar,
                                   reg_date timestamp without time zone DEFAULT now(),
                                   mod_date timestamp without time zone,
                                   exp_date timestamp without time zone
);


ALTER TABLE lm_event_response OWNER TO lifemap;

--
-- Name: lm_event_response_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_event_response_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_event_response_id_seq OWNER TO lifemap;

--
-- Name: lm_event_response_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_event_response_id_seq OWNED BY lm_event_response.id;


--
-- Name: lm_exported_event; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_exported_event (
                                   id bigint NOT NULL,
                                   event_id bigint,
                                   external_id bigint,
                                   responded_user_id bigint,
                                   responded_first_name text,
                                   responded_middle_name text,
                                   responded_last_name text,
                                   responded_phone_number text,
                                   responded_description text,
                                   responded_category text,
                                   is_responded boolean,
                                   responded_date timestamp without time zone,
                                   status character(1) DEFAULT 'A'::bpchar,
                                   reg_date timestamp without time zone DEFAULT now(),
                                   mod_date timestamp without time zone,
                                   exp_date timestamp without time zone
);


ALTER TABLE lm_exported_event OWNER TO lifemap;

--
-- Name: lm_exported_event_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_exported_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_exported_event_id_seq OWNER TO lifemap;

--
-- Name: lm_exported_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_exported_event_id_seq OWNED BY lm_exported_event.id;


--
-- Name: lm_file_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE lm_file_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_file_id_seq OWNER TO postgres;

--
-- Name: lm_file; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_file (
                         id bigint DEFAULT nextval('lm_file_id_seq'::regclass) NOT NULL,
                         content_type text,
                         filename text NOT NULL,
                         is_external boolean NOT NULL,
                         size bigint NOT NULL,
                         crypt_algorithm text,
                         crypt_base64key text,
                         is_crypted boolean,
                         data oid,
                         secured boolean,
                         session_id bigint,
                         stored_exists boolean,
                         is_stored_separate boolean,
                         stored_path text,
                         status character varying(1) DEFAULT 'A'::character varying,
                         reg_date timestamp without time zone DEFAULT now(),
                         mod_date timestamp without time zone,
                         exp_date timestamp without time zone
);


ALTER TABLE lm_file OWNER TO lifemap;

--
-- Name: lm_permission; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_permission (
                               id bigint NOT NULL,
                               name text NOT NULL,
                               description text,
                               is_active boolean DEFAULT false,
                               status character(1) DEFAULT 'A'::bpchar,
                               reg_date timestamp without time zone DEFAULT now(),
                               mod_date timestamp without time zone,
                               exp_date timestamp without time zone
);


ALTER TABLE lm_permission OWNER TO lifemap;

--
-- Name: lm_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_permission_id_seq OWNER TO lifemap;

--
-- Name: lm_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_permission_id_seq OWNED BY lm_permission.id;


--
-- Name: lm_region; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_region (
                           id bigint NOT NULL,
                           country_id bigint,
                           osm_id bigint,
                           place_id bigint,
                           code text,
                           name_en text,
                           name_ru text,
                           name_uz text,
                           name_alternative_1 text,
                           name_alternative_2 text,
                           name_alternative_3 text,
                           description text,
                           status character(1) DEFAULT 'A'::bpchar,
                           reg_date timestamp without time zone DEFAULT now(),
                           mod_date timestamp without time zone,
                           exp_date timestamp without time zone,
                           geom postgis.geometry
);


ALTER TABLE lm_region OWNER TO lifemap;

--
-- Name: lm_region_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_region_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_region_id_seq OWNER TO lifemap;

--
-- Name: lm_region_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_region_id_seq OWNED BY lm_region.id;


--
-- Name: lm_role_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE lm_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_role_id_seq OWNER TO postgres;

--
-- Name: lm_role; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_role (
                         id bigint DEFAULT nextval('lm_role_id_seq'::regclass) NOT NULL,
                         name text NOT NULL,
                         description text,
                         assigned_role boolean DEFAULT true,
                         status character varying(1) DEFAULT 'A'::character varying,
                         reg_date timestamp without time zone DEFAULT now(),
                         mod_date timestamp without time zone,
                         exp_date timestamp without time zone,
                         lowered_name text
);


ALTER TABLE lm_role OWNER TO lifemap;

--
-- Name: lm_role_permission; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_role_permission (
                                    id bigint NOT NULL,
                                    role_id bigint,
                                    permission_id bigint NOT NULL,
                                    access_value integer DEFAULT 0 NOT NULL,
                                    status character(1) DEFAULT 'A'::bpchar,
                                    reg_date timestamp without time zone DEFAULT now(),
                                    mod_date timestamp without time zone,
                                    exp_date timestamp without time zone
);


ALTER TABLE lm_role_permission OWNER TO lifemap;

--
-- Name: lm_role_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_role_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_role_permission_id_seq OWNER TO lifemap;

--
-- Name: lm_role_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_role_permission_id_seq OWNED BY lm_role_permission.id;


--
-- Name: lm_user; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_user (
                         id bigint NOT NULL,
                         login text,
                         password text,
                         first_name text,
                         middle_name text,
                         last_name text,
                         auth_type_id integer DEFAULT 1 NOT NULL,
                         ext_user_id bigint,
                         photo_url text,
                         photo_id bigint,
                         last_logged_in timestamp with time zone,
                         login_attempt integer,
                         recovery_exp timestamp without time zone,
                         recovery_key text,
                         auth_token text,
                         status character(1) DEFAULT 'A'::text,
                         reg_date timestamp without time zone DEFAULT now(),
                         mod_date timestamp without time zone,
                         exp_date timestamp without time zone,
                         is_blocked boolean DEFAULT false,
                         block_date timestamp with time zone,
                         phone_mobile text,
                         perform_blocking_user_id bigint,
                         email text,
                         region_id bigint DEFAULT 1
);


ALTER TABLE lm_user OWNER TO lifemap;

--
-- Name: lm_user_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE lm_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE lm_user_id_seq OWNER TO lifemap;

--
-- Name: lm_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE lm_user_id_seq OWNED BY lm_user.id;


--
-- Name: lm_user_role; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE lm_user_role (
                              id bigint NOT NULL,
                              user_id bigint,
                              role_id bigint,
                              status character(1) DEFAULT 'A'::bpchar,
                              reg_date timestamp without time zone DEFAULT now(),
                              mod_date timestamp without time zone,
                              exp_date timestamp without time zone
);


ALTER TABLE lm_user_role OWNER TO lifemap;

--
-- Name: test_cities; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE test_cities (
                             name text,
                             population real,
                             elevation integer
);


ALTER TABLE test_cities OWNER TO lifemap;

--
-- Name: test_capitals; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE test_capitals (
    state integer
)
    INHERITS (test_cities);


ALTER TABLE test_capitals OWNER TO lifemap;

--
-- Name: test_jsonb; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE test_jsonb (
                            id bigint NOT NULL,
                            tp_data jsonb NOT NULL
);


ALTER TABLE test_jsonb OWNER TO lifemap;

--
-- Name: test_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE test_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE test_id_seq OWNER TO lifemap;

--
-- Name: test_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE test_id_seq OWNED BY test_jsonb.id;


--
-- Name: test_jsonb_2; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE test_jsonb_2 (
                              id bigint NOT NULL,
                              tp_data jsonb NOT NULL
);


ALTER TABLE test_jsonb_2 OWNER TO lifemap;

--
-- Name: test_jsonb_2_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE test_jsonb_2_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE test_jsonb_2_id_seq OWNER TO lifemap;

--
-- Name: test_jsonb_2_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE test_jsonb_2_id_seq OWNED BY test_jsonb_2.id;


--
-- Name: test_original; Type: TABLE; Schema: public; Owner: lifemap
--

CREATE TABLE test_original (
                               id bigint NOT NULL,
                               mobject_id bigint,
                               tp_timestamp timestamp without time zone,
                               bigint_1 bigint,
                               bigint_2 bigint,
                               bigint_3 bigint,
                               text_1 text,
                               text_2 text,
                               text_3 text,
                               double_1 double precision,
                               double_2 double precision,
                               double_3 double precision,
                               boolean_1 boolean,
                               boolean_2 boolean,
                               boolean_3 boolean,
                               timestamp_1 timestamp without time zone,
                               timestamp_2 timestamp without time zone,
                               timestamp_3 timestamp without time zone,
                               integer_1 integer,
                               integer_2 integer,
                               integer_3 integer
);


ALTER TABLE test_original OWNER TO lifemap;

--
-- Name: test_original_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE test_original_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE test_original_id_seq OWNER TO lifemap;

--
-- Name: test_original_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE test_original_id_seq OWNED BY test_original.id;


--
-- Name: user_role_id_seq; Type: SEQUENCE; Schema: public; Owner: lifemap
--

CREATE SEQUENCE user_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE user_role_id_seq OWNER TO lifemap;

--
-- Name: user_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: lifemap
--

ALTER SEQUENCE user_role_id_seq OWNED BY lm_user_role.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_auth_type ALTER COLUMN id SET DEFAULT nextval('lm_auth_type_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_bot_event ALTER COLUMN id SET DEFAULT nextval('lm_bot_event_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_country ALTER COLUMN id SET DEFAULT nextval('lm_country_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event ALTER COLUMN id SET DEFAULT nextval('lm_event_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_action ALTER COLUMN id SET DEFAULT nextval('lm_event_action_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_action_type ALTER COLUMN id SET DEFAULT nextval('lm_event_action_type_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_category ALTER COLUMN id SET DEFAULT nextval('lm_event_category_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_response ALTER COLUMN id SET DEFAULT nextval('lm_event_response_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_exported_event ALTER COLUMN id SET DEFAULT nextval('lm_exported_event_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_permission ALTER COLUMN id SET DEFAULT nextval('lm_permission_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_region ALTER COLUMN id SET DEFAULT nextval('lm_region_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_role_permission ALTER COLUMN id SET DEFAULT nextval('lm_role_permission_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_user ALTER COLUMN id SET DEFAULT nextval('lm_user_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_user_role ALTER COLUMN id SET DEFAULT nextval('user_role_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY test_jsonb ALTER COLUMN id SET DEFAULT nextval('test_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY test_jsonb_2 ALTER COLUMN id SET DEFAULT nextval('test_jsonb_2_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY test_original ALTER COLUMN id SET DEFAULT nextval('test_original_id_seq'::regclass);


--
-- Name: file_pkey; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_file
    ADD CONSTRAINT file_pkey PRIMARY KEY (id);


--
-- Name: lm_auth_type_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_auth_type
    ADD CONSTRAINT lm_auth_type_pk PRIMARY KEY (id);


--
-- Name: lm_bot_event_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_bot_event
    ADD CONSTRAINT lm_bot_event_pk PRIMARY KEY (id);


--
-- Name: lm_bot_state_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_bot_user_state
    ADD CONSTRAINT lm_bot_state_pk UNIQUE (user_id, chat_id);


--
-- Name: lm_bot_user_option_pkey; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_bot_user_option
    ADD CONSTRAINT lm_bot_user_option_pkey PRIMARY KEY (user_id);


--
-- Name: lm_country_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_country
    ADD CONSTRAINT lm_country_pk PRIMARY KEY (id);


--
-- Name: lm_event_action_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_action
    ADD CONSTRAINT lm_event_action_pk PRIMARY KEY (id);


--
-- Name: lm_event_action_type_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_action_type
    ADD CONSTRAINT lm_event_action_type_pk PRIMARY KEY (id);


--
-- Name: lm_event_category_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_category
    ADD CONSTRAINT lm_event_category_pk PRIMARY KEY (id);


--
-- Name: lm_event_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event
    ADD CONSTRAINT lm_event_pk PRIMARY KEY (id);


--
-- Name: lm_event_response_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_response
    ADD CONSTRAINT lm_event_response_pk PRIMARY KEY (id);


--
-- Name: lm_exported_event_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_exported_event
    ADD CONSTRAINT lm_exported_event_pk PRIMARY KEY (id);


--
-- Name: lm_permissions_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_permission
    ADD CONSTRAINT lm_permissions_pk PRIMARY KEY (id);


--
-- Name: lm_region_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_region
    ADD CONSTRAINT lm_region_pk PRIMARY KEY (id);


--
-- Name: lm_role_permission_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_role_permission
    ADD CONSTRAINT lm_role_permission_pk PRIMARY KEY (id);


--
-- Name: lm_role_pkey; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_role
    ADD CONSTRAINT lm_role_pkey PRIMARY KEY (id);


--
-- Name: lm_user_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_user
    ADD CONSTRAINT lm_user_pk PRIMARY KEY (id);


--
-- Name: test_2_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY test_jsonb_2
    ADD CONSTRAINT test_2_pk PRIMARY KEY (id);


--
-- Name: test_original_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY test_original
    ADD CONSTRAINT test_original_pk PRIMARY KEY (id);


--
-- Name: test_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY test_jsonb
    ADD CONSTRAINT test_pk PRIMARY KEY (id);


--
-- Name: user_role_pk; Type: CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_user_role
    ADD CONSTRAINT user_role_pk PRIMARY KEY (id);


--
-- Name: lm_auth_type_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_auth_type_id_uindex ON lm_auth_type USING btree (id);


--
-- Name: lm_bot_event_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_bot_event_id_uindex ON lm_bot_event USING btree (id);


--
-- Name: lm_country_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_country_id_uindex ON lm_country USING btree (id);


--
-- Name: lm_event_action_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_event_action_id_uindex ON lm_event_action USING btree (id);


--
-- Name: lm_event_action_type_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_event_action_type_uindex ON lm_event_action_type USING btree (id);


--
-- Name: lm_event_category_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_event_category_id_uindex ON lm_event_category USING btree (id);


--
-- Name: lm_event_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_event_id_uindex ON lm_event USING btree (id);


--
-- Name: lm_event_response_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_event_response_id_uindex ON lm_event_response USING btree (id);


--
-- Name: lm_exported_event_event_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_exported_event_event_id_uindex ON lm_exported_event USING btree (event_id);


--
-- Name: lm_exported_event_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_exported_event_id_uindex ON lm_exported_event USING btree (id);


--
-- Name: lm_permissions_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_permissions_id_uindex ON lm_permission USING btree (id);


--
-- Name: lm_region_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_region_id_uindex ON lm_region USING btree (id);


--
-- Name: lm_role_permission_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_role_permission_id_uindex ON lm_role_permission USING btree (id);


--
-- Name: lm_user_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX lm_user_id_uindex ON lm_user USING btree (id);


--
-- Name: test_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX test_id_uindex ON test_jsonb USING btree (id);


--
-- Name: user_role_id_uindex; Type: INDEX; Schema: public; Owner: lifemap
--

CREATE UNIQUE INDEX user_role_id_uindex ON lm_user_role USING btree (id);


--
-- Name: change_user_role_on_update_mobile_phone; Type: TRIGGER; Schema: public; Owner: lifemap
--

CREATE TRIGGER change_user_role_on_update_mobile_phone AFTER UPDATE ON lm_user FOR EACH ROW EXECUTE PROCEDURE change_user_role_on_update_mobile_phone();


--
-- Name: create_user_role_on_user_insert; Type: TRIGGER; Schema: public; Owner: lifemap
--

CREATE TRIGGER create_user_role_on_user_insert AFTER INSERT ON lm_user FOR EACH ROW EXECUTE PROCEDURE create_user_role_on_user_insert();


--
-- Name: save_event_action; Type: TRIGGER; Schema: public; Owner: lifemap
--

CREATE TRIGGER save_event_action AFTER UPDATE ON lm_event FOR EACH ROW EXECUTE PROCEDURE save_event_action();


--
-- Name: lm_bot_event_lm_bot_event_category_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_bot_event
    ADD CONSTRAINT lm_bot_event_lm_bot_event_category_id_fk FOREIGN KEY (category_id) REFERENCES lm_event_category(id);


--
-- Name: lm_bot_event_lm_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_bot_event
    ADD CONSTRAINT lm_bot_event_lm_user_id_fk FOREIGN KEY (user_id) REFERENCES lm_user(id);


--
-- Name: lm_event_action_lm_event_action_type_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_action
    ADD CONSTRAINT lm_event_action_lm_event_action_type_id_fk FOREIGN KEY (action_type_id) REFERENCES lm_event_action_type(id);


--
-- Name: lm_event_action_lm_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_action
    ADD CONSTRAINT lm_event_action_lm_user_id_fk FOREIGN KEY (user_id) REFERENCES lm_user(id);


--
-- Name: lm_event_lm_event_category_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event
    ADD CONSTRAINT lm_event_lm_event_category_id_fk FOREIGN KEY (category_id) REFERENCES lm_event_category(id);


--
-- Name: lm_event_lm_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event
    ADD CONSTRAINT lm_event_lm_user_id_fk FOREIGN KEY (user_id) REFERENCES lm_user(id);


--
-- Name: lm_event_response_lm_event_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_response
    ADD CONSTRAINT lm_event_response_lm_event_id_fk FOREIGN KEY (event_id) REFERENCES lm_event(id);


--
-- Name: lm_event_response_lm_event_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_action
    ADD CONSTRAINT lm_event_response_lm_event_id_fk FOREIGN KEY (event_id) REFERENCES lm_event(id);


--
-- Name: lm_event_response_lm_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_event_response
    ADD CONSTRAINT lm_event_response_lm_user_id_fk FOREIGN KEY (responsed_user_id) REFERENCES lm_user(id);


--
-- Name: lm_exported_event_lm_event_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_exported_event
    ADD CONSTRAINT lm_exported_event_lm_event_id_fk FOREIGN KEY (event_id) REFERENCES lm_event(id);


--
-- Name: lm_exported_event_lm_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_exported_event
    ADD CONSTRAINT lm_exported_event_lm_user_id_fk FOREIGN KEY (responded_user_id) REFERENCES lm_user(id);


--
-- Name: lm_region_lm_country_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_region
    ADD CONSTRAINT lm_region_lm_country_id_fk FOREIGN KEY (country_id) REFERENCES lm_country(id);


--
-- Name: lm_role_permission_lm_permission_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_role_permission
    ADD CONSTRAINT lm_role_permission_lm_permission_id_fk FOREIGN KEY (permission_id) REFERENCES lm_permission(id);


--
-- Name: lm_role_permission_lm_role_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_role_permission
    ADD CONSTRAINT lm_role_permission_lm_role_id_fk FOREIGN KEY (role_id) REFERENCES lm_role(id);


--
-- Name: lm_user_lm_auth_type_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_user
    ADD CONSTRAINT lm_user_lm_auth_type_id_fk FOREIGN KEY (auth_type_id) REFERENCES lm_auth_type(id);


--
-- Name: lm_user_lm_file_id_fk_2; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_user
    ADD CONSTRAINT lm_user_lm_file_id_fk_2 FOREIGN KEY (photo_id) REFERENCES lm_file(id);


--
-- Name: lm_user_lm_region_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_user
    ADD CONSTRAINT lm_user_lm_region_id_fk FOREIGN KEY (region_id) REFERENCES lm_region(id);


--
-- Name: lm_user_role_lm_role_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_user_role
    ADD CONSTRAINT lm_user_role_lm_role_id_fk FOREIGN KEY (role_id) REFERENCES lm_role(id);


--
-- Name: lm_user_role_lm_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: lifemap
--

ALTER TABLE ONLY lm_user_role
    ADD CONSTRAINT lm_user_role_lm_user_id_fk FOREIGN KEY (user_id) REFERENCES lm_user(id);


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

