--
-- PostgreSQL database dump
--

\restrict fLyjoHfdRIbt68YHE3P6FHjH99cNf6DXTMRFqWNgPZSAxsDd4nPVkh6sfTb5uRM

-- Dumped from database version 16.14 (Ubuntu 16.14-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.14 (Ubuntu 16.14-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: cleanup_expired_sessions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_expired_sessions() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE sessions SET state = 'expired'
    WHERE expires_at < NOW() AND state != 'expired';
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: agent_handoffs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_handoffs (
    id integer NOT NULL,
    user_id integer,
    session_id integer,
    from_agent character varying(10) NOT NULL,
    to_agent character varying(10) NOT NULL,
    reason character varying(200),
    context_snapshot jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: agent_handoffs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agent_handoffs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agent_handoffs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agent_handoffs_id_seq OWNED BY public.agent_handoffs.id;


--
-- Name: atlas_destinations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atlas_destinations (
    id integer NOT NULL,
    country character varying(100) NOT NULL,
    city character varying(100) NOT NULL,
    avg_flight_cost_usd numeric(8,2),
    avg_hotel_cost_per_night_usd numeric(8,2),
    avg_recovery_days_dental integer DEFAULT 3,
    avg_recovery_days_plastic integer DEFAULT 7,
    climate_type character varying(50),
    languages character varying(100) DEFAULT 'español'::character varying,
    visa_required_us boolean DEFAULT false,
    notes text,
    is_active boolean DEFAULT true
);


--
-- Name: atlas_destinations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.atlas_destinations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: atlas_destinations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.atlas_destinations_id_seq OWNED BY public.atlas_destinations.id;


--
-- Name: conversation_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation_history (
    id integer NOT NULL,
    user_id integer,
    session_id integer,
    agent character varying(10) NOT NULL,
    role character varying(10) NOT NULL,
    message text NOT NULL,
    message_type character varying(20) DEFAULT 'text'::character varying,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: conversation_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.conversation_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: conversation_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.conversation_history_id_seq OWNED BY public.conversation_history.id;


--
-- Name: knowledge_base; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_base (
    id integer NOT NULL,
    specialty character varying(50) NOT NULL,
    procedure_name character varying(100) NOT NULL,
    procedure_key character varying(100) NOT NULL,
    required_info jsonb NOT NULL,
    critical_questions jsonb NOT NULL,
    required_exams jsonb DEFAULT '[]'::jsonb,
    typical_recovery_days integer,
    sage_intro_message text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: knowledge_base_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.knowledge_base_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: knowledge_base_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.knowledge_base_id_seq OWNED BY public.knowledge_base.id;


--
-- Name: medical_intake; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medical_intake (
    id integer NOT NULL,
    user_id integer,
    session_id integer,
    specialty character varying(50) NOT NULL,
    procedure_name character varying(100),
    collected_data jsonb DEFAULT '{}'::jsonb,
    missing_items jsonb DEFAULT '[]'::jsonb,
    completeness_score integer DEFAULT 0,
    status character varying(20) DEFAULT 'in_progress'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: medical_intake_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.medical_intake_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: medical_intake_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.medical_intake_id_seq OWNED BY public.medical_intake.id;


--
-- Name: message_dedup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_dedup (
    dedup_key character varying(120) NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: quotes_comparison; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quotes_comparison (
    id integer NOT NULL,
    user_id integer,
    intake_id integer,
    destination_city character varying(100),
    destination_country character varying(100),
    procedure_cost numeric(10,2),
    doctor_name character varying(100),
    clinic_name character varying(100),
    doctor_experience_years integer,
    additional_notes text,
    quote_data jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: quotes_comparison_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.quotes_comparison_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: quotes_comparison_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.quotes_comparison_id_seq OWNED BY public.quotes_comparison.id;


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id integer NOT NULL,
    user_id integer,
    active_agent character varying(10) DEFAULT 'NOVA'::character varying NOT NULL,
    state character varying(50) DEFAULT 'initial'::character varying,
    context jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    expires_at timestamp with time zone DEFAULT (now() + '24:00:00'::interval)
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    phone character varying(30) NOT NULL,
    name character varying(100),
    language character varying(5) DEFAULT 'es'::character varying,
    first_contact timestamp with time zone DEFAULT now(),
    last_activity timestamp with time zone DEFAULT now(),
    is_active boolean DEFAULT true,
    metadata jsonb DEFAULT '{}'::jsonb
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: agent_handoffs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_handoffs ALTER COLUMN id SET DEFAULT nextval('public.agent_handoffs_id_seq'::regclass);


--
-- Name: atlas_destinations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atlas_destinations ALTER COLUMN id SET DEFAULT nextval('public.atlas_destinations_id_seq'::regclass);


--
-- Name: conversation_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_history ALTER COLUMN id SET DEFAULT nextval('public.conversation_history_id_seq'::regclass);


--
-- Name: knowledge_base id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base ALTER COLUMN id SET DEFAULT nextval('public.knowledge_base_id_seq'::regclass);


--
-- Name: medical_intake id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_intake ALTER COLUMN id SET DEFAULT nextval('public.medical_intake_id_seq'::regclass);


--
-- Name: quotes_comparison id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes_comparison ALTER COLUMN id SET DEFAULT nextval('public.quotes_comparison_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: agent_handoffs agent_handoffs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_handoffs
    ADD CONSTRAINT agent_handoffs_pkey PRIMARY KEY (id);


--
-- Name: atlas_destinations atlas_destinations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atlas_destinations
    ADD CONSTRAINT atlas_destinations_pkey PRIMARY KEY (id);


--
-- Name: conversation_history conversation_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_history
    ADD CONSTRAINT conversation_history_pkey PRIMARY KEY (id);


--
-- Name: knowledge_base knowledge_base_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base
    ADD CONSTRAINT knowledge_base_pkey PRIMARY KEY (id);


--
-- Name: knowledge_base knowledge_base_procedure_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base
    ADD CONSTRAINT knowledge_base_procedure_key_key UNIQUE (procedure_key);


--
-- Name: medical_intake medical_intake_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_intake
    ADD CONSTRAINT medical_intake_pkey PRIMARY KEY (id);


--
-- Name: message_dedup message_dedup_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_dedup
    ADD CONSTRAINT message_dedup_pkey PRIMARY KEY (dedup_key);


--
-- Name: quotes_comparison quotes_comparison_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes_comparison
    ADD CONSTRAINT quotes_comparison_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_conv_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conv_created ON public.conversation_history USING btree (created_at);


--
-- Name: idx_conv_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conv_session_id ON public.conversation_history USING btree (session_id);


--
-- Name: idx_conv_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conv_user_id ON public.conversation_history USING btree (user_id);


--
-- Name: idx_intake_specialty; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_intake_specialty ON public.medical_intake USING btree (specialty);


--
-- Name: idx_intake_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_intake_user ON public.medical_intake USING btree (user_id);


--
-- Name: idx_kb_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kb_key ON public.knowledge_base USING btree (procedure_key);


--
-- Name: idx_kb_specialty; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kb_specialty ON public.knowledge_base USING btree (specialty);


--
-- Name: idx_one_active_session_per_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_one_active_session_per_user ON public.sessions USING btree (user_id) WHERE ((state)::text <> 'expired'::text);


--
-- Name: idx_sessions_agent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sessions_agent ON public.sessions USING btree (active_agent);


--
-- Name: idx_sessions_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sessions_expires ON public.sessions USING btree (expires_at);


--
-- Name: idx_sessions_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sessions_user_id ON public.sessions USING btree (user_id);


--
-- Name: idx_users_last_activity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_last_activity ON public.users USING btree (last_activity);


--
-- Name: idx_users_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_phone ON public.users USING btree (phone);


--
-- Name: medical_intake trg_intake_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_intake_updated_at BEFORE UPDATE ON public.medical_intake FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: sessions trg_sessions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sessions_updated_at BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: agent_handoffs agent_handoffs_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_handoffs
    ADD CONSTRAINT agent_handoffs_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE SET NULL;


--
-- Name: agent_handoffs agent_handoffs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_handoffs
    ADD CONSTRAINT agent_handoffs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: conversation_history conversation_history_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_history
    ADD CONSTRAINT conversation_history_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE SET NULL;


--
-- Name: conversation_history conversation_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_history
    ADD CONSTRAINT conversation_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: medical_intake medical_intake_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_intake
    ADD CONSTRAINT medical_intake_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE SET NULL;


--
-- Name: medical_intake medical_intake_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_intake
    ADD CONSTRAINT medical_intake_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: quotes_comparison quotes_comparison_intake_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes_comparison
    ADD CONSTRAINT quotes_comparison_intake_id_fkey FOREIGN KEY (intake_id) REFERENCES public.medical_intake(id) ON DELETE SET NULL;


--
-- Name: quotes_comparison quotes_comparison_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes_comparison
    ADD CONSTRAINT quotes_comparison_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict fLyjoHfdRIbt68YHE3P6FHjH99cNf6DXTMRFqWNgPZSAxsDd4nPVkh6sfTb5uRM

