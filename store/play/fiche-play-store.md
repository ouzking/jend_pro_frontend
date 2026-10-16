# Fiche Google Play — JËND PRO

Éléments à copier dans la Play Console. Les passages **[À COMPLÉTER]** dépendent
d'informations que seul l'éditeur peut fournir.

## Fichiers

| Élément | Fichier |
|---|---|
| App bundle (signé, clé d'import) | `build/app/outputs/bundle/release/app-release.aab` |
| Icône 512 × 512 | `store/play/icone-512.png` |
| Bannière 1024 × 500 | `store/play/banniere-1024x500.png` |
| Captures d'écran (2 à 8, téléphone) | à prendre sur le téléphone : accueil, caisse, catalogue, client, reçu, rapports |

## Fiche principale

- **Nom de l'app** (30 car. max) : `JËND PRO — Gestion commerce`
- **Description courte** (80 car. max) :
  `Caisse, stock, clients et crédits : pilotez votre commerce depuis le téléphone.`
- **Catégorie** : Entreprise (Business)
- **Adresse e-mail de contact** : ousmanearfangkemobodian@gmail.com (provisoire, à remplacer par une adresse pro)
- **Site web** (facultatif) : [À COMPLÉTER]

### Description complète

```
JËND PRO est l'application de gestion pensée pour les commerçants : boutiques,
quincailleries, alimentations, dépôts. Vendez, suivez votre stock et vos crédits
clients, et voyez en un coup d'œil comment se porte votre commerce.

CAISSE RAPIDE
• Encaissez en quelques secondes : recherche, scan du code-barres, favoris
• Dictez la vente : « deux sacs de riz et une huile 5 litres » (français et wolof)
• Espèces, Wave, Orange Money, carte, virement, ou plusieurs moyens pour une même vente
• Vente à crédit avec plafond par client
• Fonctionne même sans réseau : les ventes sont envoyées dès le retour de la connexion

STOCK ET PRODUITS
• Catalogue avec photos, prix, codes-barres et catégories
• Stock par boutique ou dépôt, alertes de stock faible
• Inventaires, ajustements, transferts entre emplacements

CLIENTS ET FOURNISSEURS
• Dettes clients, règlements et relevé de compte en PDF
• Achats fournisseurs, réceptions de marchandise et paiements

REÇUS ET FACTURES
• Ticket de caisse (imprimante thermique 58 ou 80 mm), facture A4
• Partage en PDF ou par WhatsApp

PILOTAGE
• Chiffre d'affaires, marge estimée, panier moyen, meilleures ventes
• Trésorerie et dépenses (loyer, électricité, transport…) avec justificatifs
• Notifications en direct : ventes importantes, stock faible

ÉQUIPE
• Invitez caissiers, gérants et magasiniers : chacun ne voit que ce que son rôle permet
• Journal des actions sensibles

Vos données sont protégées : connexion chiffrée et droits d'accès vérifiés par le
serveur pour chaque action.
```

## Contenu de l'application (Play Console → « Contenu de l'application »)

- **Politique de confidentialité** : URL publique de `docs/confidentialite.html`
  (ex. GitHub Pages : `https://ouzking.github.io/jend_pro_frontend/confidentialite.html`)
- **Accès à l'application** : « Certaines fonctionnalités nécessitent une connexion » →
  fournir un compte de test (e-mail + mot de passe) avec un commerce déjà configuré.
- **Annonces** : Non, l'application ne contient pas d'annonces.
- **Classification du contenu** : questionnaire → catégorie « Utilitaire / productivité »,
  aucune violence, aucun contenu sensible → classification « Tout public » attendue.
- **Public cible** : 18 ans et plus (outil professionnel).
- **Application d'actualités** : Non. **Application gouvernementale** : Non.
- **Fonctionnalités financières** : l'app enregistre des ventes et des crédits entre un
  commerçant et ses clients ; elle **ne fournit pas** de service de paiement, de prêt ni
  de transfert d'argent → déclarer « aucune de ces fonctionnalités ».
- **Suppression de compte** : bouton « Supprimer mon compte » dans *Plus → Mon profil*
  (demande envoyée au support) + URL web `docs/suppression-compte.html`.

### Sécurité des données (formulaire « Data safety »)

| Question | Réponse |
|---|---|
| Collecte ou partage de données ? | Oui (collecte) |
| Données chiffrées en transit ? | Oui (HTTPS) |
| L'utilisateur peut demander la suppression ? | Oui |
| Partage avec des tiers ? | Non (l'hébergeur agit comme sous-traitant) |

Données collectées (toutes : **collectées, non partagées, obligatoires sauf mention**,
finalités « Fonctionnement de l'app » et « Gestion du compte ») :

- Informations personnelles : **nom**, **adresse e-mail**, **numéro de téléphone** (facultatif)
- Informations financières : **autres informations financières** (ventes, paiements,
  dettes clients, dépenses saisies par le commerçant)
- Photos : **photos** (produits, logo, justificatifs — facultatif)
- Autres contenus générés : fiches clients, fournisseurs, employés, produits

- Audio : **enregistrements vocaux** → « traités de façon éphémère », non conservés, non
  envoyés aux serveurs JËND PRO ; transcription par le service de reconnaissance vocale du
  téléphone, seulement quand l'utilisateur appuie sur le micro (finalité : fonctionnement de l'app).
  Permission Android déclarée : `RECORD_AUDIO`.

- Infos et performances de l'app : **journaux de plantage** et **diagnostics** (Sentry, sans données
  personnelles) → collectés, non partagés, finalité « Analyse / correction des erreurs » — seulement si
  `SENTRY_DSN` est configuré.

Non collectés : position, contacts, historique de navigation, identifiants publicitaires,
données de santé, messages. Aucun outil d'analyse ni de publicité n'est intégré.

## Avant la publication en production

1. Compte développeur **personnel** créé après novembre 2023 : Google impose un **test
   fermé avec au moins 12 testeurs pendant 14 jours** avant l'accès à la production
   (pas pour un compte d'organisation).
2. Supabase : réactiver « Confirm email », configurer un SMTP (Resend, Brevo…), ajouter
   `io.jendpro.app://auth-callback` aux Redirect URLs.
3. `SUPPORT_EMAIL` renseigné (provisoire) : le remplacer par l'adresse pro dans `env/prod.json` et `docs/*.html`, puis reconstruire.
