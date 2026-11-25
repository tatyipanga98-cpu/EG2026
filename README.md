# EG2026 – États généraux (Kinshasa Ouest)

Application web progressive (PWA) des États généraux : présences, délégués, recommandations, restitutions des ateliers.

## Structure
- `index.html` : application (connexion Supabase).
- `public/` : manifeste PWA, service worker, icône.
- `supabase/schema.sql` : schéma de la base (tables, rôles, règles RLS).

## Déploiement
Hébergement : Vercel (fichiers statiques, sans étape de build).
Base de données : Supabase, projet `pjwpmudfbhgasmsuziny`.

## Sécurité
Seule la clé publique (`sb_publishable_…`) est dans le code. Ne jamais committer la clé `service_role` ni de mot de passe.
