# LiVrai

Application web de gestion de livraisons (Java Servlets / JSP, Tomcat, MySQL).

## Lancement avec Docker (recommandé)

Prérequis : Docker et le plugin Docker Compose.

### 1. Configuration

Copier le fichier d'exemple et renseigner vos propres valeurs :
```
cp .env.example .env
```

Variables disponibles :

| Variable | Rôle | Défaut |
| --- | --- | --- |
| `MYSQL_ROOT_PASSWORD` | Mot de passe root MySQL | aucun, à renseigner |
| `MYSQL_DATABASE` | Nom de la base | `livrai` |
| `MYSQL_USER` | Utilisateur applicatif | `livrai` |
| `MYSQL_PASSWORD` | Mot de passe applicatif | aucun, à renseigner |
| `DB_HOST_PORT` | Port MySQL exposé sur l'hôte | `3307` |
| `APP_HOST_PORT` | Port HTTP exposé sur l'hôte | `8080` |

Le fichier `.env` contient des secrets, il est ignoré par git et ne doit jamais être commité.

Ces deux ports ne servent qu'à joindre les conteneurs depuis la machine hôte, les conteneurs communiquent entre eux par le réseau Docker. Si le démarrage échoue avec `address already in use` ou `port is already allocated`, c'est qu'un autre service occupe déjà le port : choisir une autre valeur dans `.env`. Pour identifier le coupable :
```
ss -lntp | grep -E ':(3307|8080)\b'
```
`DB_HOST_PORT` vaut 3307 et non 3306 par défaut, car un MySQL installé localement occupe généralement déjà 3306.

### 2. Démarrage

```
docker compose up --build -d
```

Deux conteneurs sont lancés :
- `db` : MySQL 8, le schéma `db/init-script.sql` est appliqué automatiquement à la première création du volume
- `app` : build Maven du WAR puis déploiement sur Tomcat 9

Visiter http://localhost:8080/app (ou le port choisi via `APP_HOST_PORT`).

### 3. 1ère connexion

Il est nécessaire de créer un utilisateur admin en base. Se connecter au client MySQL du conteneur, qui demandera le mot de passe défini dans `MYSQL_PASSWORD` :
```
docker compose exec db mysql -u livrai -p livrai
```
puis
```
INSERT INTO user (email, name, password, admin) VALUES
  ('<email>', 'Livrai', '<password>', TRUE);
```

### Commandes utiles

```
docker compose logs -f app      # suivre les logs Tomcat
docker compose up --build -d    # reconstruire après modification du code
docker compose down             # arrêter (les données sont conservées)
docker compose down -v          # arrêter et supprimer la base
```

## Mise en place de l'environnement de développement sous Eclipse

### Initialisation de la base de données
Télécharger MySql 8

Créer un utilisateur

Créer une nouvelle base de données nommée `livrai`

Appliquer le script SQL db/init-script.sql

### Lancement du serveur
Télécharger Eclipse (un jdk > 6 est nécessaire)

Importer le projet Maven dans Eclipse.

Télécharger tomcat 8.5 et l'ajouter à la vue Server d'Eclipse.

Ajouter le projet `app` au server.

Lancer le serveur.

Visiter l'URL localhost:8080/app

### Configuration de la connexion
La connexion à la base est lue depuis les variables d'environnement `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` et `DB_PASSWORD` (voir `AbstractDao.java`). En l'absence de ces variables, les valeurs par défaut sont `localhost`, `3306`, `livrai`, `root` et `password`. Définir ces variables dans la configuration de lancement du serveur Eclipse pour pointer vers votre base locale.
