# JËND PRO — application mobile commerçants

Application Flutter officielle de JËND PRO (caisse, stock, clients, crédits, achats,
dépenses, tableau de bord). Le backend est le projet Supabase du dépôt
`jend_pro_backend` : **la base est la source de vérité** (RLS, RPC, calculs).

## Lancer l'application

1. Copier `env/dev.example.json` en `env/dev.json` et renseigner :
   - `SUPABASE_URL` : URL du projet (local : `http://10.0.2.2:54421` depuis l'émulateur Android,
     `http://127.0.0.1:54421` sinon) ;
   - `SUPABASE_PUBLISHABLE_KEY` : clé **publishable** (`npx supabase status` dans le dépôt backend,
     ou Dashboard → Project Settings → API Keys).
2. `flutter run --dart-define-from-file=env/dev.json`

Téléphone Android en USB avec le backend local : `adb reverse tcp:54421 tcp:54421` puis
`SUPABASE_URL = http://127.0.0.1:54421` (le HTTP n'est autorisé que dans le manifeste debug).

Sans configuration, l'app affiche un écran « Configuration manquante ».

> **Jamais** de clé `service_role` / secrète dans ce dépôt ni dans l'app.

Comptes de démo (backend local uniquement, mot de passe `jendpro-demo`) :
`owner@demo.jendpro.local` (OWNER), `cashier@demo.jendpro.local` (CASHIER).

### Liens profonds (mot de passe oublié)

Les e-mails Supabase redirigent vers `io.jendpro.app://auth-callback` (configurable via
`AUTH_REDIRECT_URL`). Cette URL doit figurer dans **Auth → URL Configuration → Redirect URLs**
du projet Supabase (en local : `additional_redirect_urls` de `supabase/config.toml` du backend).

## Architecture

```text
lib/
  app/                    assemblage : MaterialApp, routeur, shell de navigation, splash
    router/               routes.dart (chemins), redirect.dart (règles pures, testées)
    shell/                barre de navigation / rail tablette, bouton « Vendre »
  core/
    config/               Env (--dart-define)
    design_system/        jetons (couleurs, typo, espacements…), thème, composants Jp*
    errors/               AppFailure : traduction du contrat d'erreurs backend
    formatting/           montants FCFA (entiers), quantités, dates
    permissions/          catalogue des permissions + PermissionSet
    storage/ supabase/    providers d'infrastructure
    validation/           validateurs alignés sur les contraintes SQL
  features/<domaine>/
    data/                 repositories : SEUL endroit qui appelle Supabase
    domain/               modèles typés
    application/          contrôleurs / providers Riverpod
    presentation/         écrans et widgets
```

Règles :

- L'UI n'appelle jamais Supabase directement ; les repositories convertissent toute exception
  en `AppFailure` (message français prêt à afficher).
- Les permissions (`get_my_permissions`) servent uniquement à adapter l'UI ; la base revérifie tout.
- Montants = `int` (francs CFA), jamais `double`. Les totaux de référence viennent du serveur.
- Pas de valeurs de style en dur dans les écrans : `context.palette`, `JpSpacing`, `JpTypography`…
- Chaque écran gère chargement (squelettes), vide, erreur + réessayer.

## Avancement

| Phase | État |
|---|---|
| 1. Architecture | ✅ |
| 2. Design system | ✅ |
| 3. Routing (garde auth / entreprise / permissions, shell adaptatif) | ✅ |
| 4. Authentification (connexion, inscription, oubli, réinitialisation, changement, déconnexion) | ✅ |
| 5. Onboarding (création / invitations → type → informations → logo → produits → stock initial) | ✅ |
| 6. Tableau de bord (CA, variation, histogramme, panier moyen, bénéfice, dépenses, créances, stock faible, top produits, dernières ventes ; périodes) | ✅ |
| 7. Produits (liste paginée, recherche, scan, catégories, fiche, création / modification, photo, archivage) | ✅ |
| 8. Stock (onglet Stock, filtres faible / rupture / emplacement, ajouts, pertes, casse, inventaire physique, transferts, historique) | ✅ |
| 9. Caisse (grille, recherche, scan, favoris, panier, remises, client, paiements multiples, monnaie, crédit, file hors ligne idempotente, reçu, historique, annulation) | ✅ |
| 10. Clients (liste, débiteurs, fiche, relevé de compte, règlements, plafond de crédit, reprise du cahier, appel / rappel WhatsApp, archivage) | ✅ |
| 11. Fournisseurs (liste, « à payer », fiche, contact, produits fournis, dettes calculées en base, achats récents) | ✅ |
| 12. Achats (saisie, produits du fournisseur et dernier coût, commande, acomptes, réception stock + coût moyen, paiements, annulation) | ✅ |
| 13. Dépenses (saisie rapide, catégories, justificatif privé + URL signée, mois, total serveur) | ✅ |
| 14. Équipe (invitation via Edge Function, rôles attribuables, suspension, retrait, quitter ; fiches employés et salaires) | ✅ |
| 15. Reçus et factures (ticket thermique 58/80 mm, facture A4, relevé client PDF, aperçu, impression, partage, WhatsApp) | ✅ |
| 16. Notifications (centre, temps réel, bandeau en direct, invitations, tout lire, seuil « vente importante ») | ✅ |
| 17. Rapports (plages, comparaison, graphique CA/marge/ventes, trésorerie, meilleures ventes, export PDF) et journal d'audit | ✅ |
| 18 → 20 | à venir |

## Qualité

```bash
flutter analyze
flutter test
```

## Identité visuelle

Charte « Forêt, Menthe Signal, Laiton » (maquettes de marque) : vert forêt institutionnel,
point lumineux Menthe Signal, dorure laiton en accent rare. Monogramme : un « J » couronné de
deux carrés (le tréma du Ë), dessiné en code (`JpMonogram`). Icônes de l'app générées depuis
`assets/branding/` : `dart run flutter_launcher_icons`.

Polices (SIL Open Font License) : Plus Jakarta Sans pour l'interface, Jost pour le wordmark.

Tests d'intégration contre un Supabase réel (backend local) :
`flutter test test/integration -j 1 --dart-define-from-file=env/dev.json`
(séquentiel : chaque suite crée un compte, et Supabase Auth limite les inscriptions simultanées).
