# Synchro et serveur d’atelier

Avec un **serveur BenchLog** sur le réseau de l’atelier, tous les Mac partagent une bibliothèque. Chaque Mac en garde une copie complète et fonctionne hors ligne; les changements passent dans les deux sens quelques secondes après les avoir faits, et chaque minute.

## Utiliser ce Mac comme serveur

Le serveur le plus simple est un Mac qui reste allumé à l’atelier, avec BenchLog dessus :

1. Ouvrez **Réglages > Synchro** et choisissez **Utiliser ce Mac comme serveur**.
2. Si macOS le demande, autorisez BenchLog dans **Réglages Système > Général > Éléments de connexion**, puis choisissez à nouveau le bouton.
3. Les réglages montrent ce que les autres Mac entrent : l’**adresse**, comme `http://Bench-Mac.local:8420`, et le **jeton**, chacun avec **Copier**.

Le serveur continue de tourner quand BenchLog est fermé et après un redémarrage, et le Mac ne se met pas en veille de lui-même tant qu’il sert. **Ne plus utiliser ce Mac comme serveur…** l’arrête ; ses données restent dans le dossier qu’ouvre **Afficher le dossier de données**.

## Installer le serveur sur un NAS

Le serveur tourne aussi sur un NAS ou un autre ordinateur toujours allumé, avec Docker ou avec Node 24.

```
cd server
docker build -t benchlog-server .
docker run -d --name benchlog --restart unless-stopped \
  -p 8420:8420 -v benchlog-data:/data benchlog-server
docker logs benchlog
```

La dernière commande affiche le **jeton**, une seule fois. Sur un Mac, OrbStack ou Docker Desktop fait tourner Docker. Le dossier `server` et son README sont dans le code source de BenchLog sur GitHub.

Pour joindre le serveur hors de l’atelier, installez Tailscale sur le serveur et sur chaque Mac, et utilisez le nom Tailscale du serveur comme adresse.

## Connecter le premier Mac

1. Ouvrez **Réglages > Synchro**.
2. Entrez l’adresse du serveur, comme `http://bench-mac.local:8420`, et le jeton.
3. Choisissez **Tester la connexion**, puis **Connecter**. La bibliothèque monte sur le serveur.

## Rejoindre depuis un autre Mac

Le serveur garde une bibliothèque. Pour l’utiliser sur un autre Mac :

1. Sur le premier Mac, copiez la **clé de bibliothèque** dans Réglages > Synchro.
2. Sur l’autre Mac, entrez l’adresse et le jeton, puis la clé de bibliothèque, et choisissez **Remplacer la bibliothèque de ce Mac…**. BenchLog sauvegarde d’abord la bibliothèque de ce Mac.

## Ce que vous voyez

- Le bas de la barre latérale montre la dernière synchro, et **Synchroniser**.
- **Hors ligne** veut dire que le serveur est hors d’atteinte. Continuez à travailler : les changements attendent et partent à son retour. Les nouvelles réparations prennent leur numéro dans une réserve de numéros de dossier.
- Les factures et les notes de crédit demandent le serveur, pour que leurs numéros ne se répètent jamais.
- Les codes des appareils sont scellés avec la clé de bibliothèque avant de quitter le Mac. Gardez la clé en lieu sûr : sans elle, un nouveau Mac ne peut pas se joindre.
