# Carpeta `app/` — cliente Flutter

El proyecto Flutter se crea en el hito **0B** con:

```bash
flutter create --org co.edu.uniminuto.demo --project-name campus_app \
  --platforms android,web app
```

La estructura interna seguirá §7.1:

```
app/lib/
├── core/        # config, api, cache, sync, security, router, theme, widgets
└── features/    # auth, carnet, validador, aulas, horarios, academico, perfil, admin, comunicacion
```

Mientras 0B no se ejecute, esta carpeta solo documenta la intención para que el monorepo conserve
la estructura de §7.1.
