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
