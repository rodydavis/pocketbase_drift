package main

import (
	"log"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"

	"pocketbase_drift_example_backend/middleware"
	_ "pocketbase_drift_example_backend/migrations"
	"pocketbase_drift_example_backend/routes"
	"pocketbase_drift_example_backend/services"
)

func main() {
	app := pocketbase.New()

	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{Automigrate: false})

	lab := middleware.NewLab()

	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		if err := services.Seed(app, 60); err != nil {
			return err
		}
		routes.Register(app, se, lab)
		return se.Next()
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
