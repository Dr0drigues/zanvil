# ==============================================================================
# Project Scaffold - Bootstrapper de projet
# ==============================================================================
# Genere la structure standard pour Node/TypeScript ou Java
# ==============================================================================

proj_scaffold() {
    local project_type=""
    local project_name=""
    local target_dir="."

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type|-t) shift; project_type="$1"; shift ;;
            --name|-n) shift; project_name="$1"; shift ;;
            -d)        shift; target_dir="$1"; shift ;;
            -h|--help) _proj_scaffold_help; return 0 ;;
            *)
                # Premier arg sans flag = nom du projet
                if [[ -z "$project_name" ]]; then
                    project_name="$1"
                fi
                shift
                ;;
        esac
    done

    # Interactif si pas de type
    if [[ -z "$project_type" ]]; then
        _ui_header "Project Scaffold"
        echo ""
        echo "  ${_ui_bold}Types disponibles:${_ui_nc}"
        echo "    ${_ui_cyan}1${_ui_nc}) node       Node.js / TypeScript"
        echo "    ${_ui_cyan}2${_ui_nc}) java       Java / Maven"
        echo ""
        local choice
        printf "  Choix [1-2]: "
        read -r choice
        case "$choice" in
            1|node) project_type="node" ;;
            2|java) project_type="java" ;;
            *)
                _ui_msg_fail "Type invalide"
                return 1
                ;;
        esac
    fi

    # Nom du projet
    if [[ -z "$project_name" ]]; then
        printf "  Nom du projet: "
        read -r project_name
        [[ -z "$project_name" ]] && { _ui_msg_fail "Nom requis"; return 1; }
    fi

    # Creer le dossier
    local project_dir="$target_dir/$project_name"
    if [[ -d "$project_dir" ]]; then
        _ui_msg_fail "Le dossier '$project_dir' existe deja"
        return 1
    fi

    mkdir -p "$project_dir"

    _ui_header "Scaffold: $project_name ($project_type)"
    echo ""

    # Fichiers communs
    _proj_scaffold_common "$project_dir" "$project_name"

    # Fichiers specifiques
    case "$project_type" in
        node) _proj_scaffold_node "$project_dir" "$project_name" ;;
        java) _proj_scaffold_java "$project_dir" "$project_name" ;;
        *)
            _ui_msg_fail "Type inconnu: $project_type"
            return 1
            ;;
    esac

    # Git init
    git -C "$project_dir" init -q 2>/dev/null
    _proj_scaffold_log "git init"

    echo ""
    _ui_separator 44
    _ui_msg_ok "Projet $project_name cree dans $project_dir"
    echo ""
    _ui_msg_info "cd $project_dir"
}

# ==============================================================================
# Helper : log de creation
# ==============================================================================
_proj_scaffold_log() {
    printf "  ${_ui_green}${_ui_check}${_ui_nc} %s\n" "$1"
}

# ==============================================================================
# Fichiers communs (tous types)
# ==============================================================================
_proj_scaffold_common() {
    local dir="$1" name="$2"

    # .editorconfig
    cat > "$dir/.editorconfig" <<'EOF'
root = true

[*]
indent_style = space
indent_size = 2
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.{java,kt}]
indent_size = 4

[Makefile]
indent_style = tab
EOF
    _proj_scaffold_log ".editorconfig"

    # .proj (zsh-env project file)
    cat > "$dir/.proj" <<EOF
name: $name
path: $dir
EOF
    _proj_scaffold_log ".proj"

    # .zsh-env.local (vide, pret a remplir)
    cat > "$dir/.zsh-env.local" <<EOF
# Variables d'environnement locales pour $name
# Sera auto-source par zsh-env au cd
EOF
    _proj_scaffold_log ".zsh-env.local"

    # README.md
    cat > "$dir/README.md" <<EOF
# $name

## Getting Started

TODO

## Development

TODO
EOF
    _proj_scaffold_log "README.md"
}

# ==============================================================================
# Node.js / TypeScript
# ==============================================================================
_proj_scaffold_node() {
    local dir="$1" name="$2"

    # .gitignore
    cat > "$dir/.gitignore" <<'EOF'
node_modules/
dist/
build/
coverage/
.env
.env.local
*.log
.DS_Store
.idea/
.vscode/
*.tsbuildinfo
EOF
    _proj_scaffold_log ".gitignore"

    # .nvmrc
    echo "22" > "$dir/.nvmrc"
    _proj_scaffold_log ".nvmrc"

    # package.json
    cat > "$dir/package.json" <<EOF
{
  "name": "$name",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "tsx watch src/index.ts",
    "test": "jest",
    "lint": "eslint src/",
    "format": "prettier --write 'src/**/*.ts'"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "tsx": "^4.0.0",
    "@types/node": "^22.0.0"
  }
}
EOF
    _proj_scaffold_log "package.json"

    # tsconfig.json
    cat > "$dir/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist"]
}
EOF
    _proj_scaffold_log "tsconfig.json"

    # src/
    mkdir -p "$dir/src"
    cat > "$dir/src/index.ts" <<EOF
console.log('Hello from $name');
EOF
    _proj_scaffold_log "src/index.ts"

    # Dockerfile
    cat > "$dir/Dockerfile" <<'EOF'
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package*.json ./
RUN npm ci --production
EXPOSE 3000
CMD ["node", "dist/index.js"]
EOF
    _proj_scaffold_log "Dockerfile"

    # .github/workflows/ci.yml
    mkdir -p "$dir/.github/workflows"
    cat > "$dir/.github/workflows/ci.yml" <<'EOF'
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npm run build
      - run: npm test
EOF
    _proj_scaffold_log ".github/workflows/ci.yml"
}

# ==============================================================================
# Java / Maven
# ==============================================================================
_proj_scaffold_java() {
    local dir="$1" name="$2"

    # Convertir le nom en package-friendly (lowercase, dots)
    local pkg_name=$(echo "$name" | tr '-' '.' | tr '[:upper:]' '[:lower:]')
    local pkg_path=$(echo "$pkg_name" | tr '.' '/')

    # .gitignore
    cat > "$dir/.gitignore" <<'EOF'
target/
*.class
*.jar
*.war
*.ear
.idea/
*.iml
.vscode/
.settings/
.classpath
.project
.env
.DS_Store
*.log
EOF
    _proj_scaffold_log ".gitignore"

    # .sdkmanrc
    cat > "$dir/.sdkmanrc" <<'EOF'
java=21.0.2-tem
maven=3.9.6
EOF
    _proj_scaffold_log ".sdkmanrc"

    # pom.xml
    cat > "$dir/pom.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.${pkg_name}</groupId>
    <artifactId>${name}</artifactId>
    <version>0.1.0-SNAPSHOT</version>
    <packaging>jar</packaging>

    <properties>
        <java.version>21</java.version>
        <maven.compiler.source>\${java.version}</maven.compiler.source>
        <maven.compiler.target>\${java.version}</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.12.1</version>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.2.5</version>
            </plugin>
        </plugins>
    </build>
</project>
EOF
    _proj_scaffold_log "pom.xml"

    # Structure Maven
    mkdir -p "$dir/src/main/java/com/$pkg_path"
    mkdir -p "$dir/src/main/resources"
    mkdir -p "$dir/src/test/java/com/$pkg_path"

    cat > "$dir/src/main/java/com/$pkg_path/App.java" <<EOF
package com.$pkg_name;

public class App {
    public static void main(String[] args) {
        System.out.println("Hello from $name!");
    }
}
EOF
    _proj_scaffold_log "src/main/java/.../App.java"

    cat > "$dir/src/test/java/com/$pkg_path/AppTest.java" <<EOF
package com.$pkg_name;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class AppTest {
    @Test
    void shouldRun() {
        assertDoesNotThrow(() -> App.main(new String[]{}));
    }
}
EOF
    _proj_scaffold_log "src/test/java/.../AppTest.java"

    # Dockerfile
    cat > "$dir/Dockerfile" <<'EOF'
FROM maven:3.9-eclipse-temurin-21-alpine AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
EOF
    _proj_scaffold_log "Dockerfile"

    # .github/workflows/ci.yml
    mkdir -p "$dir/.github/workflows"
    cat > "$dir/.github/workflows/ci.yml" <<'EOF'
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
          cache: maven
      - run: mvn verify -B
EOF
    _proj_scaffold_log ".github/workflows/ci.yml"
}

# ==============================================================================
# Aide
# ==============================================================================
_proj_scaffold_help() {
    _ui_header "Project Scaffold"
    echo ""
    printf "${_ui_bold}Usage:${_ui_nc}\n"
    echo "  proj scaffold                           Interactif"
    echo "  proj scaffold --type node my-app        Node.js/TypeScript"
    echo "  proj scaffold --type java my-service    Java/Maven"
    echo ""
    printf "${_ui_bold}Types:${_ui_nc}\n"
    echo "  node    Node.js / TypeScript (package.json, tsconfig, Dockerfile, CI)"
    echo "  java    Java / Maven (pom.xml, structure Maven, Dockerfile, CI)"
    echo ""
    printf "${_ui_bold}Options:${_ui_nc}\n"
    echo "  --type, -t <type>    Type de projet"
    echo "  --name, -n <name>    Nom du projet"
    echo "  -d <dir>             Dossier parent (defaut: .)"
    echo ""
    printf "${_ui_bold}Fichiers communs:${_ui_nc}\n"
    echo "  .editorconfig, .proj, .zsh-env.local, README.md, git init"
}
