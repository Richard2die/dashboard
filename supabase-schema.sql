-- ============================================================
-- STUDIO PUNTO DIRITTI - Dashboard Schema
-- Eseguire nell'SQL Editor di Supabase
-- ============================================================

-- Abilita estensione UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- TABELLA PROFILI UTENTE (estende auth.users di Supabase)
-- ============================================================
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  full_name TEXT NOT NULL,
  display_name TEXT,
  role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('admin', 'user')),
  avatar_color TEXT DEFAULT '#1e3a5f',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABELLA CATEGORIE
-- ============================================================
CREATE TABLE public.categories (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  name TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#f97316',
  icon TEXT DEFAULT '📋',
  is_global BOOLEAN DEFAULT TRUE,        -- TRUE = predefinita per tutti
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Categorie predefinite dello studio
INSERT INTO public.categories (name, color, icon, is_global, created_by) VALUES
  ('Contenzioso', '#dc2626', '⚖️', TRUE, NULL),
  ('Scadenze Fiscali', '#ea580c', '📅', TRUE, NULL),
  ('Paghe & HR', '#2563eb', '💼', TRUE, NULL),
  ('Conciliazione', '#7c3aed', '🤝', TRUE, NULL),
  ('Immigrazione', '#059669', '🌍', TRUE, NULL),
  ('Consulenza', '#0891b2', '💬', TRUE, NULL),
  ('Amministrativo', '#64748b', '📁', TRUE, NULL),
  ('Formazione GOL', '#d97706', '🎓', TRUE, NULL);

-- ============================================================
-- TABELLA TASK PRINCIPALI
-- ============================================================
CREATE TABLE public.tasks (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
  assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,  -- NULL = task globale studio
  created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  due_date DATE,
  due_time TIME,
  is_urgent BOOLEAN DEFAULT FALSE,
  is_completed BOOLEAN DEFAULT FALSE,
  completed_at TIMESTAMPTZ,
  completed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  visibility TEXT DEFAULT 'studio' CHECK (visibility IN ('personal', 'studio')),  -- personal o visibile a tutti
  notes TEXT,
  recurring_template_id UUID,  -- riferimento al template ricorrente (FK aggiunta dopo)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABELLA TASK RICORRENTI (template)
-- ============================================================
CREATE TABLE public.recurring_templates (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
  assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  frequency TEXT NOT NULL CHECK (frequency IN ('daily', 'weekly', 'monthly', 'yearly')),
  -- Per weekly: giorno della settimana (0=Dom, 1=Lun, ... 6=Sab)
  day_of_week INTEGER CHECK (day_of_week BETWEEN 0 AND 6),
  -- Per monthly: giorno del mese (1-31)
  day_of_month INTEGER CHECK (day_of_month BETWEEN 1 AND 31),
  -- Per yearly: mese (1-12) e giorno
  month_of_year INTEGER CHECK (month_of_year BETWEEN 1 AND 12),
  -- Ora di scadenza
  due_time TIME,
  is_urgent BOOLEAN DEFAULT FALSE,
  visibility TEXT DEFAULT 'studio' CHECK (visibility IN ('personal', 'studio')),
  is_active BOOLEAN DEFAULT TRUE,
  notes TEXT,
  last_generated DATE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Aggiunge FK tra tasks e recurring_templates
ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_recurring_template_fk
  FOREIGN KEY (recurring_template_id)
  REFERENCES public.recurring_templates(id) ON DELETE SET NULL;

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_templates ENABLE ROW LEVEL SECURITY;

-- PROFILES: tutti possono leggere, ognuno modifica il proprio
CREATE POLICY "Profiles leggibili da tutti" ON public.profiles
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Profilo modificabile dal proprietario" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Profilo inseribile al signup" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- CATEGORIES: tutti leggono, ognuno inserisce le proprie, admin modifica globali
CREATE POLICY "Categorie leggibili da tutti" ON public.categories
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Utente inserisce categoria personale" ON public.categories
  FOR INSERT WITH CHECK (
    auth.uid() = created_by OR
    (is_global = TRUE AND EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
    ))
  );

CREATE POLICY "Utente modifica propria categoria" ON public.categories
  FOR UPDATE USING (
    created_by = auth.uid() OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "Utente elimina propria categoria" ON public.categories
  FOR DELETE USING (
    created_by = auth.uid() AND is_global = FALSE
  );

-- TASKS: tutti leggono, ognuno modifica i propri
CREATE POLICY "Task leggibili da tutti" ON public.tasks
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Task inseribili da utenti autenticati" ON public.tasks
  FOR INSERT WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Task modificabili dal creatore" ON public.tasks
  FOR UPDATE USING (auth.uid() = created_by);

CREATE POLICY "Task eliminabili dal creatore" ON public.tasks
  FOR DELETE USING (auth.uid() = created_by);

-- RECURRING TEMPLATES: tutti leggono, ognuno modifica i propri
CREATE POLICY "Template leggibili da tutti" ON public.recurring_templates
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Template inseribili da utenti autenticati" ON public.recurring_templates
  FOR INSERT WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Template modificabili dal creatore" ON public.recurring_templates
  FOR UPDATE USING (auth.uid() = created_by);

CREATE POLICY "Template eliminabili dal creatore" ON public.recurring_templates
  FOR DELETE USING (auth.uid() = created_by);

-- ============================================================
-- TRIGGER: aggiorna updated_at automaticamente
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tasks_updated_at BEFORE UPDATE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER recurring_updated_at BEFORE UPDATE ON public.recurring_templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- TRIGGER: crea profilo automaticamente al signup
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, display_name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'role', 'user')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- INDICI per performance
-- ============================================================
CREATE INDEX idx_tasks_due_date ON public.tasks(due_date);
CREATE INDEX idx_tasks_assigned_to ON public.tasks(assigned_to);
CREATE INDEX idx_tasks_created_by ON public.tasks(created_by);
CREATE INDEX idx_tasks_is_completed ON public.tasks(is_completed);
CREATE INDEX idx_tasks_is_urgent ON public.tasks(is_urgent);
CREATE INDEX idx_recurring_frequency ON public.recurring_templates(frequency);

-- ============================================================
-- VISTA: task con dettagli completi (utile per query frontend)
-- ============================================================
CREATE VIEW public.tasks_detailed AS
SELECT
  t.*,
  c.name AS category_name,
  c.color AS category_color,
  c.icon AS category_icon,
  p_assigned.full_name AS assigned_name,
  p_assigned.display_name AS assigned_display,
  p_created.full_name AS creator_name,
  p_created.display_name AS creator_display
FROM public.tasks t
LEFT JOIN public.categories c ON t.category_id = c.id
LEFT JOIN public.profiles p_assigned ON t.assigned_to = p_assigned.id
LEFT JOIN public.profiles p_created ON t.created_by = p_created.id;

-- ============================================================
-- FINE SCHEMA
-- Dopo aver eseguito questo script:
-- 1. Vai su Authentication > Settings e configura il tuo dominio GitHub Pages
-- 2. Copia l'URL e la ANON KEY del progetto Supabase
-- 3. Inseriscili in index.html e dashboard.html
-- ============================================================
