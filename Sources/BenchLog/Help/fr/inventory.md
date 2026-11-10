# Pièces et inventaire

La page **Pièces** liste ce que vous gardez sur l’étagère, avec la quantité, le coût, le prix et les modèles compatibles.

## Une pièce

- Le **type** dit ce que c’est : Pièce, Accessoire, Câble, Manette ou Fourniture. Le filtre de la barre d’outils affiche un seul type.
- L’**état** est Neuf, Usagé ou Remis à neuf. L’**emplacement** est son étagère, son bac ou son tiroir; la recherche le trouve.
- Le **coût** est ce que vous avez payé pour une unité, le **prix** ce que paie le client. La **marge** est la différence.
- **Sur des réparations** liste les réparations qui utilisent la pièce.

## Ajouter par code-barres

**Fichier > Ajouter par code-barres…** (⇧⌘B) ajoute les jeux, manettes et accessoires en boîte à partir du CUP ou de l’EAN sur la boîte. Utilisez un lecteur USB ou Bluetooth, ou tapez les chiffres et appuyez sur Retour.

- Un code-barres que l’inventaire connaît ajoute une unité au stock de cette pièce.
- Un nouveau code-barres est recherché sur upcitemdb.com et devient une pièce avec une unité en stock. Seul le code-barres est envoyé. Utilisez **Modifier…** pour régler son type, son coût et son prix.
- Si rien n’est trouvé, tapez son nom. La recherche gratuite permet 100 codes-barres par jour.

Une cartouche ou un disque sans boîte n’a pas de code-barres : ajoutez-le avec **Nouvelle pièce** et le type **Jeu**.

## Pièces de départ

**Fichier > Ajouter des pièces de départ** ajoute les pièces, accessoires, câbles et manettes habituels d’une console (Sony PS1, Sony PS2, Microsoft Xbox) avec un stock à zéro et un prix suggéré. Les pièces que vous avez déjà ne changent pas. Utilisez ensuite **Compter…** pour ce qui est sur l’étagère, et mettez votre coût et votre prix.

## Stock

- Une pièce est en **Stock bas** quand sa quantité atteint son seuil ou passe dessous. Le badge de la barre latérale les compte.
- L’**Historique du stock** liste chaque mouvement, du plus récent au plus ancien, avec sa raison : installée sur une réparation, reçue, comptée, endommagée, vendue, et le dossier ou la facture d’origine.
- **Compter…** met le stock à ce qu’il y a sur l’étagère; l’écart est noté.
- **Retirer endommagées…** sort les unités brisées ou perdues.

## Réapprovisionnement

Une commande de réapprovisionnement est une commande à un fournisseur.

1. **Commander plus** sur une pièce, ou **Ajouter les pièces en stock bas** pour toutes les pièces en stock bas. Les pièces vont au brouillon de leur fournisseur.
2. **Marquer commandée** quand vous passez la commande.
3. **Recevoir** quand elle arrive : les pièces entrent en stock à leur nouveau coût.

**À commander** et **En route** listent les pièces que les réparations ouvertes attendent encore.

## Valeur du stock

Les [[reports|Rapports]] montrent l’inventaire au coût à la fin de la période : les pièces sur l’étagère, plus les appareils de l’atelier en stock ou à vendre.
