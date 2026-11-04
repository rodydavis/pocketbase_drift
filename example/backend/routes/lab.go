// Package routes registers the lab control API (/api/lab/*).
//
// The lab API has no auth: the server binds to 127.0.0.1 only and the
// device reaches it through `adb reverse`.
package routes

import (
	"fmt"
	"net/http"

	"github.com/pocketbase/pocketbase/core"

	"pocketbase_drift_example_backend/middleware"
	"pocketbase_drift_example_backend/services"
)

type mutateBody struct {
	Collection string         `json:"collection"`
	ID         string         `json:"id"`
	Data       map[string]any `json:"data"`
}

// Register binds the lab routes and the global chaos/stats middleware.
func Register(app core.App, se *core.ServeEvent, lab *middleware.Lab) {
	se.Router.BindFunc(lab.Handler)

	g := se.Router.Group("/api/lab")

	g.GET("/stats", func(e *core.RequestEvent) error {
		return e.JSON(http.StatusOK, lab.Stats())
	})
	g.POST("/stats/reset", func(e *core.RequestEvent) error {
		lab.ResetStats()
		return e.NoContent(http.StatusNoContent)
	})

	g.GET("/chaos", func(e *core.RequestEvent) error {
		return e.JSON(http.StatusOK, lab.Chaos())
	})
	g.POST("/chaos", func(e *core.RequestEvent) error {
		var c middleware.ChaosConfig
		if err := e.BindBody(&c); err != nil {
			return e.BadRequestError("invalid chaos body", err)
		}
		lab.SetChaos(c)
		app.Logger().Info("lab chaos set", "mode", c.Mode, "match", c.Match, "latencyMs", c.LatencyMs)
		return e.JSON(http.StatusOK, lab.Chaos())
	})

	g.POST("/seed-big", func(e *core.RequestEvent) error {
		var body struct {
			Count int    `json:"count"`
			Group string `json:"group"`
		}
		if err := e.BindBody(&body); err != nil {
			return e.BadRequestError("invalid seed body", err)
		}
		if body.Group == "" {
			body.Group = "g"
		}
		if err := services.SeedBig(app, body.Count, body.Group); err != nil {
			return e.InternalServerError("seed failed", err)
		}
		return e.JSON(http.StatusOK, map[string]any{"inserted": body.Count})
	})

	// Server-side writes that bypass API rules: "another device" edits.
	g.POST("/mutate", func(e *core.RequestEvent) error {
		var body mutateBody
		if err := e.BindBody(&body); err != nil {
			return e.BadRequestError("invalid mutate body", err)
		}
		rec, err := app.FindRecordById(body.Collection, body.ID)
		if err != nil {
			return e.NotFoundError("record not found", err)
		}
		for k, v := range body.Data {
			rec.Set(k, v)
		}
		if err := app.Save(rec); err != nil {
			return e.BadRequestError("save failed", err)
		}
		return e.JSON(http.StatusOK, rec)
	})
	g.POST("/create", func(e *core.RequestEvent) error {
		var body mutateBody
		if err := e.BindBody(&body); err != nil {
			return e.BadRequestError("invalid create body", err)
		}
		col, err := app.FindCollectionByNameOrId(body.Collection)
		if err != nil {
			return e.NotFoundError("collection not found", err)
		}
		rec := core.NewRecord(col)
		if body.ID != "" {
			rec.Id = body.ID
		}
		for k, v := range body.Data {
			rec.Set(k, v)
		}
		if err := app.Save(rec); err != nil {
			return e.BadRequestError("save failed", err)
		}
		return e.JSON(http.StatusOK, rec)
	})
	g.POST("/delete", func(e *core.RequestEvent) error {
		var body mutateBody
		if err := e.BindBody(&body); err != nil {
			return e.BadRequestError("invalid delete body", err)
		}
		rec, err := app.FindRecordById(body.Collection, body.ID)
		if err != nil {
			return e.NotFoundError("record not found", err)
		}
		if err := app.Delete(rec); err != nil {
			return e.BadRequestError("delete failed", err)
		}
		return e.NoContent(http.StatusNoContent)
	})
	g.GET("/record/{collection}/{id}", func(e *core.RequestEvent) error {
		rec, err := app.FindRecordById(e.Request.PathValue("collection"), e.Request.PathValue("id"))
		if err != nil {
			return e.NotFoundError("record not found", err)
		}
		return e.JSON(http.StatusOK, rec)
	})
	g.GET("/count/{collection}", func(e *core.RequestEvent) error {
		n, err := app.CountRecords(e.Request.PathValue("collection"))
		if err != nil {
			return e.BadRequestError("count failed", err)
		}
		return e.JSON(http.StatusOK, map[string]any{"count": n})
	})

	// Realtime control: list and forcibly drop SSE clients (simulates a
	// network blip the SDK must recover from).
	g.GET("/realtime", func(e *core.RequestEvent) error {
		out := []map[string]any{}
		for id, c := range app.SubscriptionsBroker().Clients() {
			out = append(out, map[string]any{"id": id, "subscriptions": c.Subscriptions()})
		}
		return e.JSON(http.StatusOK, out)
	})
	g.POST("/realtime/drop", func(e *core.RequestEvent) error {
		n := 0
		for _, c := range app.SubscriptionsBroker().Clients() {
			c.Discard()
			n++
		}
		app.Logger().Info("lab dropped realtime clients", "count", n)
		return e.JSON(http.StatusOK, map[string]any{"dropped": n})
	})

	g.GET("/ping", func(e *core.RequestEvent) error {
		return e.String(http.StatusOK, fmt.Sprintf("lab ok %s", app.Settings().Meta.AppName))
	})
}
