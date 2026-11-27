-- EG2026 : schéma Supabase (PostgreSQL)
-- À exécuter dans un projet DÉDIÉ à EG2026.

create extension if not exists "pgcrypto";

-- Rôles applicatifs
create type eg_role as enum ('administrateur','secretariat','facilitateur','rapporteur','delegue','apotre');
create type eg_statut as enum ('propose','consolide','adopte');
create type eg_jour as enum ('samedi','dimanche');
create type eg_axe as enum ('A','B','C','D','E','F');

-- Profils liés aux comptes d'authentification
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nom text not null,
  role eg_role not null default 'delegue',
  created_at timestamptz not null default now()
);

-- Structures : 10 Kin, C.A. Inkisi (province), 5 commissions
create table structures (
  id smallint primary key,
  nom text not null unique,
  type text not null check (type in ('kin','province','commission'))
);

insert into structures (id, nom, type) values
 (1,'Kin-Centre 1','kin'),(2,'Kin-Centre 2','kin'),(3,'Kin-Menkao','kin'),
 (4,'Kin-Aéro','kin'),(5,'Kinshasa Nord','kin'),(6,'Kin-Sud','kin'),
 (7,'Kin-Sud-Est','kin'),(8,'Kin-Sud-Ouest','kin'),(9,'Kin-Ouest','kin'),
 (10,'Kinshasa Est','kin'),
 (11,'C.A. Inkisi (Kongo-Central)','province'),
 (12,'CTM – Commission Territoriale de Musique','commission'),
 (13,'CTJ – Commission Territoriale de la Jeunesse','commission'),
 (14,'CTED – Commission Territoriale de l''École de dimanche','commission'),
 (15,'CTE – Commission Territoriale d''Enseignement','commission'),
 (16,'Commission Audiovisuelle','commission');

-- Délégués (nominatif ; le total de référence est 53)
create table delegues (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  prenom text not null,
  structure_id smallint not null references structures(id),
  user_id uuid unique references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Présences : une ligne par délégué et par journée
create table presences (
  delegue_id uuid not null references delegues(id) on delete cascade,
  jour eg_jour not null,
  present boolean not null default false,
  saisi_par uuid references profiles(id),
  updated_at timestamptz not null default now(),
  primary key (delegue_id, jour)
);

-- Ateliers (6) et restitutions
create table ateliers (
  id smallint primary key check (id between 1 and 6),
  titre text not null
);
insert into ateliers (id, titre) values
 (1,'Atelier 1'),(2,'Atelier 2'),(3,'Atelier 3'),
 (4,'Atelier 4'),(5,'Atelier 5'),(6,'Atelier 6');

create table restitutions (
  atelier_id smallint primary key references ateliers(id),
  contenu text not null default '',
  auteur uuid references profiles(id),
  updated_at timestamptz not null default now()
);

-- Recommandations : axes A à F, statut Proposé → Consolidé → Adopté
create table recommandations (
  id uuid primary key default gen_random_uuid(),
  axe eg_axe not null,
  texte text not null check (length(trim(texte)) > 0),
  statut eg_statut not null default 'propose',
  atelier_id smallint references ateliers(id),
  auteur uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Journal des changements de statut (traçabilité)
create table statut_historique (
  id bigint generated always as identity primary key,
  recommandation_id uuid not null references recommandations(id) on delete cascade,
  ancien eg_statut,
  nouveau eg_statut not null,
  par uuid references profiles(id),
  at timestamptz not null default now()
);

-- Fonction utilitaire : rôle de l'utilisateur courant
create or replace function current_role_eg() returns eg_role
language sql stable security definer set search_path = public as $$
  select role from profiles where id = auth.uid()
$$;

-- Sécurité RLS
alter table profiles enable row level security;
alter table structures enable row level security;
alter table delegues enable row level security;
alter table presences enable row level security;
alter table ateliers enable row level security;
alter table restitutions enable row level security;
alter table recommandations enable row level security;
alter table statut_historique enable row level security;

-- Profils : chacun lit le sien ; l'administrateur gère tout
create policy profiles_lire on profiles for select
  using (id = auth.uid() or current_role_eg() in ('administrateur','secretariat'));
create policy profiles_admin on profiles for all
  using (current_role_eg() = 'administrateur')
  with check (current_role_eg() = 'administrateur');

-- Référentiels : lecture pour tout utilisateur connecté
create policy structures_lire on structures for select using (auth.uid() is not null);
create policy ateliers_lire on ateliers for select using (auth.uid() is not null);

-- Délégués : lecture pour tous les connectés ; écriture par le secrétariat et l'administrateur
create policy delegues_lire on delegues for select using (auth.uid() is not null);
create policy delegues_ecrire on delegues for all
  using (current_role_eg() in ('administrateur','secretariat'))
  with check (current_role_eg() in ('administrateur','secretariat'));

-- Présences : lecture pour les connectés ; saisie par le secrétariat, l'administrateur, les facilitateurs
create policy presences_lire on presences for select using (auth.uid() is not null);
create policy presences_ecrire on presences for all
  using (current_role_eg() in ('administrateur','secretariat','facilitateur'))
  with check (current_role_eg() in ('administrateur','secretariat','facilitateur'));

-- Restitutions : rédaction par facilitateurs et rapporteurs ; lecture pour les connectés
create policy restitutions_lire on restitutions for select using (auth.uid() is not null);
create policy restitutions_ecrire on restitutions for all
  using (current_role_eg() in ('administrateur','secretariat','facilitateur','rapporteur'))
  with check (current_role_eg() in ('administrateur','secretariat','facilitateur','rapporteur'));

-- Recommandations : création par les contributeurs ; changement de statut par le secrétariat
create policy reco_lire on recommandations for select using (auth.uid() is not null);
create policy reco_creer on recommandations for insert
  with check (current_role_eg() in ('administrateur','secretariat','facilitateur','rapporteur','delegue'));
create policy reco_modifier on recommandations for update
  using (current_role_eg() in ('administrateur','secretariat'))
  with check (current_role_eg() in ('administrateur','secretariat'));
create policy reco_supprimer on recommandations for delete
  using (current_role_eg() = 'administrateur');

-- Historique : lecture pour les connectés ; écrit automatiquement par le déclencheur
create policy histo_lire on statut_historique for select using (auth.uid() is not null);

-- Déclencheur : horodatage et journal des statuts
create or replace function eg_maj_reco() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' and new.statut is distinct from old.statut then
    insert into statut_historique (recommandation_id, ancien, nouveau, par)
    values (new.id, old.statut, new.statut, auth.uid());
  end if;
  return new;
end $$;

create trigger reco_maj before insert or update on recommandations
  for each row execute function eg_maj_reco();

-- Vue de synthèse pour le tableau de bord
create view tableau_bord with (security_invoker = true) as
select
  (select count(*) from delegues) as total_delegues,
  (select count(*) from presences where present and jour = 'samedi') as presents_samedi,
  (select count(*) from presences where present and jour = 'dimanche') as presents_dimanche,
  (select count(*) from recommandations) as recommandations_total,
  (select count(*) from recommandations where statut = 'propose') as propose,
  (select count(*) from recommandations where statut = 'consolide') as consolide,
  (select count(*) from recommandations where statut = 'adopte') as adopte;

-- ===== Migration eg2026_durcissement_et_temps_reel (déjà appliquée) =====
alter view public.tableau_bord set (security_invoker = true);
revoke execute on function public.current_role_eg() from public, anon;
grant execute on function public.current_role_eg() to authenticated;
revoke execute on function public.eg_maj_reco() from public, anon, authenticated;
alter table public.delegues add constraint delegues_nom_prenom_structure_uniq unique (nom, prenom, structure_id);
create index if not exists delegues_structure_idx on public.delegues(structure_id);
create index if not exists reco_statut_idx on public.recommandations(statut);
create index if not exists presences_jour_idx on public.presences(jour);
alter publication supabase_realtime add table public.presences, public.recommandations, public.delegues, public.restitutions;

-- ===== Migration eg2026_modules_delegues_audit (déjà appliquée) =====
-- Comptes désactivables, titre des délégués, tables programme / tâches / documents / livrables,
-- journal d'activité (audit_log + déclencheurs) et rôle sensible au statut actif.
-- Les 58 délégués et les 2 séances du programme ont été chargés depuis la liste officielle
-- (Liste_delegues_EG2026.pdf) et l'affiche. Voir l'historique des migrations du projet Supabase.
alter table public.profiles add column if not exists actif boolean not null default true;
alter table public.delegues add column if not exists titre text;
create or replace function public.current_role_eg() returns eg_role
language sql stable security definer set search_path = public as $$
  select role from profiles where id = auth.uid() and actif
$$;
create table public.programme (id uuid primary key default gen_random_uuid(), jour text not null check (jour in ('samedi','dimanche')), debut time, fin time, titre text not null, lieu text, notes text, created_at timestamptz not null default now());
create table public.taches (id uuid primary key default gen_random_uuid(), titre text not null, description text, responsable text, echeance date, statut text not null default 'a_faire' check (statut in ('a_faire','en_cours','fait')), created_at timestamptz not null default now());
create table public.documents (id uuid primary key default gen_random_uuid(), titre text not null, categorie text, lien text, notes text, created_at timestamptz not null default now());
create table public.livrables (id uuid primary key default gen_random_uuid(), titre text not null, statut text not null default 'a_faire' check (statut in ('a_faire','en_cours','livre')), echeance date, lien text, notes text, created_at timestamptz not null default now());
create table public.audit_log (id bigint generated always as identity primary key, user_id uuid, table_name text not null, op text not null, row_id text, detail text, at timestamptz not null default now());
-- Lecture : tout utilisateur connecté. Écriture : programme et tâches = administrateur, secrétariat ;
-- documents et livrables = + rapporteur. Journal : lecture administrateur, secrétariat.
-- Déclencheur eg_audit() sur delegues, recommandations, taches, programme, documents, livrables, profiles.

-- ===== Migration secretariat_technique_programme_ateliers_suivi (déjà appliquée) =====
-- programme : code, intervenant, ordre, statut (a_confirmer / confirme / realise) ; 27 séances du programme officiel
-- ateliers : facilitateurs officiels ; restitutions : rapporteur, six questions-guides (q1..q6), statut (a_faire / en_cours / remise)
-- questions : questions de la salle (salle / écrit / en ligne), réponses, statut ; RLS : lecture connectés, écriture secrétariat
-- suivi_structures : fiche de désignation, diagnostic, lien et test de connexion, point focal ; RLS : écriture secrétariat
-- recommandations : source (atelier / memo / plenière), ref ; 13 propositions du mémo initial (statut proposé)
-- taches : 20 tâches du calendrier (pré-événement et post-événement)
-- delegues : telephone, domaine, mode (presentiel / distance) ; Jean Bosco Pongo à distance

-- ===== Migration budget_et_programme_final (déjà appliquée) =====
-- parametres (taux_usd_cdf = 2350), budget_lignes (rubriques traiteur / location / communication / imprevu, devise USD ou CDF),
-- budget_depenses (rattachées à une ligne, devise héritée de la ligne). RLS : administrateur et secrétariat uniquement.
-- Totaux chargés depuis le document officiel : 1 682 $ et 205 100 FC (arrondi du document : 1 770 $ avec imprévu).
-- Programme officiel remplacé par la version finale (28 séquences). Atelier 6 : Prêtre Prince Masua et les modérateurs.