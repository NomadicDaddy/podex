## Podex - PowerShell/Pode + htmx Framework for Building Web Applications

### Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Technical Stack](#technical-stack)
- [Setup](#setup)
- [Running the Project](#running-the-project)
- [Contributing](#contributing)
- [License](#license)

### Introduction

Podex is a framework for building full-stack web applications using PowerShell/Pode for the backend and htmx for the frontend.

### Features

- **Home page:** overview of Podex and its technology choices as a server-rendered Pode view.
- **CRUD Manager:** list, search, paginate, add, update, and delete items against SQLite via htmx and client-side Mustache templates, with loading, empty, and error states.
- **File-based JSON API:** `GET/POST/PUT/DELETE /api/crud` with parameterized SQLite queries and validated, status-coded responses.
- **htmx fragment endpoint:** HTML-only partial responses (e.g. the add-item modal form).
- **OpenAPI + Swagger:** spec at `/docs/openapi` and interactive UI at `/docs/swagger` for `/api/*`.
- **Pode view engine:** layouts, partials, and reusable components with Tailwind CSS theming (light/dark compatible).
- **Debug-only routes:** database init/clear and server-stop helpers, registered only when `Podex.Debug` is enabled.
- **Quality gates:** formatting, ESLint, PSScriptAnalyzer, Pester tests, Tailwind CSS build, and knip via `bun` scripts, plus foreground/background server lifecycle (`dev`/`start`/`stop`) and an aggregate `smoke:qc`.

### Technical Stack

- **Backend**: [PowerShell Core](https://github.com/PowerShell/PowerShell), [Pode](https://github.com/Badgerati/Pode), [SQLite](https://www.sqlite.org/index.html)
- **Frontend**: [htmx](https://htmx.org/), [Mustache](https://mustache.github.io/), [Tailwind CSS](https://tailwindcss.com/)

### Setup

1. Clone the repository:

    ```sh
    git clone https://github.com/NomadicDaddy/podex.git
    cd podex
    ```

2. Install dependencies:

    ```sh
    bun install
    ```

3. Install PowerShell modules:
    ```sh
    powershell -Command ". ./.build.ps1"
    ```

### Running the Project

1. Start the server:

    ```sh
    bun run start
    ```

2. Open your browser and navigate to `http://localhost:8433`.

### Contributing

1. Fork the repository.
2. Create a new branch (`git checkout -b feature-branch`).
3. Make your changes.
4. Commit your changes (`git commit -am 'Add new feature'`).
5. Push to the branch (`git push origin feature-branch`).
6. Create a new Pull Request.

### License

This project is licensed under the MIT License.
