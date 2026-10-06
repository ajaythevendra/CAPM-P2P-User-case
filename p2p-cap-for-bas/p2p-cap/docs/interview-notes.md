# CAP Interview Notes – P2P Project

## Phase 1 – Domain Modeling (CDS)

### Project layout
- `db/` domain model + `db/data/*.csv` initial data (file name = `<namespace>-<Entity>.csv`)
- `srv/` service definitions (`.cds`) + handlers (`.js` with the same name)
- `app/` UI apps (Fiori Elements, annotations)
- `package.json` → `cds` section holds config/profiles (`[development]`, `[hybrid]`, `[production]`)

### Association vs. Composition
| | Association | Composition |
|---|---|---|
| Meaning | Reference ("knows") | Containment ("owns") |
| Lifecycle | Independent | Children are created/deleted with the parent (cascade) |
| Deep insert/update | No | Yes – `POST` a PO with its `items` in one request |
| Draft | Children not part of the draft | Whole composition tree is part of the draft |
| Example here | `PurchaseOrders.supplier` | `PurchaseOrders.items`, `POItems.scheduleLines` |

- **Managed** association: `supplier : Association to Suppliers` → CAP generates FK `supplier_ID`.
- **Unmanaged** association: explicit `on` condition, e.g. `goodsReceipts : Association to many GoodsReceipts on goodsReceipts.purchaseOrder = $self` (no FK on the parent side).
- `$self` = the current entity instance (used for backlinks).
- `up_` is CAP's naming convention for the backlink from child to parent (generated automatically for *Composition of aspects*: `items : Composition of many { ... }`).

### Reuse aspects from `@sap/cds/common`
- `cuid` → `key ID : UUID` (generated automatically on INSERT)
- `managed` → `createdAt/createdBy/modifiedAt/modifiedBy` (`@cds.on.insert` / `@cds.on.update`)
- `Currency`, `Country`, `Language` → association to `sap.common.Currencies` etc.
- `sap.common.CodeList` → `name`, `descr` (localized) → generates `*_texts` table + `localized` view
- `@sap/cds-common-content` delivers ready-made currency/country/language data.

### Why UUID keys + a separate readable number (`poNo`)?
- UUIDs can be generated client-side, without a DB round trip; no collisions in multitenancy or replication; required by draft for new documents.
- Business numbers (4500000001) come from a number range → see `NumberRanges` (Phase 2: `SELECT ... FOR UPDATE` to avoid duplicates under concurrency; on HANA you could also use a sequence).

### Useful annotations used in the model
- `@mandatory` – value required (checked by the generic input validation)
- `@readonly` – ignored on client writes (calculated by the server)
- `@assert.range: [1,5]` – range check; on enums it checks the allowed values
- `default 'NEW'` – DB default
- `enum { APPROVED; REJECTED; }` – type-level constraint

### CAP vs. RAP mapping (common interview question)
| CAP | RAP |
|---|---|
| CDS entity in `db/` | Database table + CDS view entity (interface view) |
| Service projection | Projection view + service definition/binding |
| Composition | Composition / `association to parent` |
| Event handlers (`before/on/after`) | Behavior implementation (determinations, validations) |
| `@restrict` | DCL (access control) + authorization master |
| Draft (`@odata.draft.enabled`) | `with draft;` in BDEF |

### Quick commands
- `cds watch` – run with live reload (SQLite in-memory by default in development)
- `cds compile srv -2 sql` – show generated DDL
- `cds compile srv -2 edmx` – show OData metadata
- `cds env` – show the effective configuration

---

## Phase 2 – Services & Business Logic

### Why several services instead of one?
- A service = an **API tailored to a use case / persona** (RequisitionService for requesters/approvers, PurchasingService for buyers, InvoiceService for AP).
- Each exposes only what that role needs (`@readonly` value helps, slim projections like `RequisitionService.PurchaseOrders { ID, poNo, ... }`).
- Makes authorization simpler (Phase 4: `@requires` per service) and keeps the OData metadata small.
- Auto-exposure: composition children (`PRItems`) and `@cds.autoexpose` entities (all `sap.common.CodeList`s) are exposed automatically.

### Event handler phases
| Phase | Use for | Example here |
|---|---|---|
| `before` | Validation, defaults, calculations on `req.data` | totals, number assignment, blocked supplier check |
| `on` | Replace / implement the operation (actions, custom reads) | `submit`, `approve`, `postGoodsReceipt` |
| `after` | Post-processing results, side effects | update PO invoiced quantities after invoice save |

- `req.error()` collects errors (all are returned together, shown per field in Fiori via the `target` such as `in/items(0)/quantity`). `req.reject()` throws immediately.
- `req.info()` / `req.warn()` → messages in the `sap-messages` header → toast / message popover in Fiori.
- **Gotcha we hit:** generic input validation (`@mandatory`, `@assert.*`) runs *before* custom `before` handlers, so a value you want to default in a handler must not be `@mandatory`. Here, `SupplierInvoices.supplier` was made `@readonly` and derived from the PO.
- **Gotcha we hit:** in `after('CREATE')` the result can contain only the keys, so read business data from `req.data`.

### Draft (lean draft, the default since CAP 8)
- `@odata.draft.enabled` → CAP creates `*.drafts` tables plus the actions `draftEdit`, `draftPrepare`, `draftActivate`.
- OData `POST` to a draft-enabled entity creates a **draft** (`IsActiveEntity=false`); `draftActivate` turns it into an active `CREATE` (new) or `UPDATE` (edit) carrying the **full deep document**. So `before(['CREATE','UPDATE'])` sees all items, which makes it the right place for totals and validations.
- Events: `NEW` on `X.drafts` (draft created → defaults), `EDIT` on `X` (edit pressed → status checks), `PATCH` on `X.drafts` (field changes), `DISCARD`.
- Handlers registered on `X` apply to active data only; use `X.drafts` for draft data.
- Bound actions on draft-enabled entities need the full key: `PurchaseOrders(ID=...,IsActiveEntity=true)/PurchasingService.release`.
- In RAP the equivalent is `with draft;` in the BDEF plus `determine action Prepare`, with `Activate`/`Edit`/`Discard` as draft actions.

### Actions vs. functions
- **Action** = side effects (POST), e.g. `approve`. **Function** = read-only (GET), e.g. `getOpenQuantity()`.
- **Bound** (to an entity instance, `req.params[0]` holds the key) vs. **unbound** (service level).
- Structured / array parameters: `items : many GRItemInput`.
- `@mandatory` on parameters is validated automatically (`reject(@mandatory comment)`).

### Number ranges and concurrency
- `UPDATE NumberRanges SET current = current + 1` **first**, then read it. On HANA the UPDATE takes a row lock until commit, so parallel transactions are serialized and no duplicates are possible.
- Alternatives: a HANA sequence (`.hdbsequence` + native SQL), or `SELECT ... FOR UPDATE` (`SELECT.one.from(X).forUpdate()`).
- The same lock-then-read pattern is needed for goods receipts posted in parallel on the same PO item (otherwise there's a lost-update risk on `receivedQuantity`).

### CQL patterns used
- Deep read: `SELECT.one.from(PurchaseOrders, ID, po => { po('*'), po.items('*') })`
- Deep insert: `INSERT.into(PurchaseOrders).entries({ ..., items: [{ ..., scheduleLines: [...] }] })`
- Aggregation: `.columns('poItem_ID', 'sum(quantity) as qty').groupBy('poItem_ID')`
- Subquery: `.where({ up__ID: { in: SELECT('ID').from(SupplierInvoices).where({ purchaseOrder_ID }) } })`
- Expression update: `UPDATE(X).where({ object }).with('current = current + 1')`
- Writes inside actions go to **db entities** (`cds.entities('p2p')`), not the service projections. This bypasses `@readonly` and draft checks on purpose, because the server owns status fields.

### Business rules implemented (good to explain in an interview)
- **Approval:** auto-approved below 10,000; otherwise approver limit ≥ amount, no self-approval (segregation of duties), with a full approval log.
- **Status machines:** PR `NEW→SUB→APR/REJ→ORD`; PO `NEW→REL→PGR→GRC→INV→CLS` (or `CAN`); Invoice `NEW→MAT/BLK→APR→PAI`.
- **Goods receipt:** only for released POs; 5% over-delivery tolerance.
- **3-way match:** price variance ≤ 2% and invoiced qty (incl. other invoices) ≤ received qty; otherwise `BLK`. An AP override is possible with a reason.

### Testing
- `cds.test(__dirname + '/..')` starts the server in-process (SQLite in-memory) and gives `GET/POST/...` with mocked users (`auth: { username: 'carol' }`).
- Works with `node --test`, jest, mocha and vitest. Run here with `npm test`.

---

## Phase 3 – Fiori Elements UI

### Where annotations live
- `app/common.cds` → annotations on the **domain model** (`p2p.*`): labels (`@title`), texts (`@Common.Text` + `TextArrangement`), units/currencies (`@Measures.*`), value helps. Every service and app inherits them.
- `app/<app>/annotations.cds` → **service-level** layout per app: `UI.LineItem`, `UI.Facets`, `UI.HeaderInfo`, actions, side effects.
- CAP loads `app/*.cds` and `app/*/*.cds` automatically (`cds env get roots`).

### App anatomy (what the Fiori generator creates)
- `webapp/manifest.json`: `sap.app.dataSources` (OData V4 service), `sap.ui5.routing` (List Report → Object Page → sub-object page), `crossNavigation.inbounds` (semantic object + action, used by Work Zone tiles), `sap.cloud.service` (HTML5 repo / managed approuter).
- `Component.js` extends `sap/fe/core/AppComponent`; there are no views or controllers, because everything comes from annotations.
- **Relative** service URI (`odata/v4/...`): on BTP the app is served by the HTML5 repo under its own path, and the approuter's `xs-app.json` routes `odata/...` to the CAP backend. Locally, `cds watch` (`@sap/cds-fiori`) redirects `/<app>/webapp/odata/...` → `/odata/...` automatically.

### Key annotations used
| Annotation | Effect |
|---|---|
| `UI.SelectionFields` | filter bar fields |
| `UI.LineItem` (+ `UI.Importance: #High`) | table columns; low-importance columns go to the pop-in on narrow screens |
| `UI.HeaderInfo`, `UI.HeaderFacets`, `UI.DataPoint` | object page title + header KPIs |
| `UI.Facets` → `UI.FieldGroup` / `items/@UI.LineItem` | sections: forms and sub-tables |
| `UI.Identification` / `UI.DataFieldForAction` in LineItem | action buttons on the object page / table toolbar |
| `Core.OperationAvailable` (`$edmJson` expression on `in/status_code`) | action enabled per row / status |
| `UI.UpdateHidden` / `UI.DeleteHidden` (dynamic) | hide Edit/Delete depending on status |
| `Common.SideEffects` | which fields/entities to reload after a change or action |
| `Common.SemanticKey: [prNo]` | readable URLs `PurchaseRequisitions('10000007')` + draft indicator |
| `Common.ValueList` (+ `ValueListParameterIn`) | value help, filtered by another field (PO items of the chosen PO) |
| `@cds.odata.valuelist` on an entity | CAP generates the value help for every association to it |
| `Common.FilterDefaultValue` | default filter (approvers see "Submitted" first) |
| `Criticality` | colours/icons for status fields (0 neutral, 1 red, 2 yellow, 3 green, 5 blue) |

### Side effects end-to-end (common deep-dive question)
1. User changes `quantity` in a draft item → FE sends `PATCH PRItems(ID=..,IsActiveEntity=false)`.
2. CAP `before('PATCH', PRItems.drafts)` computes `netAmount`; `after` recalculates the header total in the **draft table**.
3. `@Common.SideEffects { SourceProperties:[quantity], TargetProperties:['netAmount','up_/totalAmount'] }` tells FE to re-read those fields → the UI shows the new total without a save.
- **Gotcha we hit:** Fiori's *inline creation rows* send the first entered value as a **POST** (draft `NEW`), not a PATCH, so handle both.
- In RAP: determinations `on modify` + side effects in the BDEF (`side effects { field quantity affects field netAmount; }`).

### Gotchas found while testing
- **Auto-exposed entities** (composition children) can only be reached via navigation; a value help that reads them directly fails with `ENTITY_IS_AUTOEXPOSED`, so expose them explicitly in the service.
- Without `@requires`, mocked auth never challenges → user is `anonymous` → defaults from the employee record are empty.
- `cds watch` may not pick up every file change on Windows; restart it if the UI doesn't reflect annotation changes.
- **White screen although data loads:** a standalone `index.html` needs `html, body, body > div, #container, #container-uiarea { height: 100%; }`. Fiori Elements pages are `height:100%`, so without it the app renders at 0px. (In the Work Zone/FLP the shell provides the height.)
- Action parameters of type `many <structure>` can't be rendered in the FE dialog → `@UI.Hidden` on the parameter, server-side default ("receive all open quantities").

---

## Phase 4 – Security (Authentication & Authorization)

### Authentication vs. authorization
- **Authentication** = who are you? On BTP: XSUAA (or SAP Cloud Identity Services/IAS) issues a **JWT**. The approuter handles the login (OAuth2 authorization-code flow) and forwards the JWT to CAP, which validates it with `@sap/xssec`.
- **Authorization** = what may you do? Scopes in the JWT → CAP roles → `@requires` / `@restrict`.
- Locally: `auth.kind: mocked` with users, roles and attributes in `package.json` (`[development]` profile). In production: `"auth": "xsuaa"` (added by `cds add xsuaa`).

### The three layers in CAP (see `srv/access-control.cds`)
| Layer | Annotation | Example | Result if violated |
|---|---|---|---|
| Service | `@requires: ['Buyer','Admin']` | only buyers enter PurchasingService | 403 |
| Event / action | `@restrict: [{ grant: ['READ','release'], to: 'Buyer' }]` | warehouse can't `release` | 403 |
| Instance (rows) | `where: 'plant_code = $user.plant'` | bob only sees plant 1000/1100 POs | filtered list / 404 on single read |

- `where: 'requester_userId = $user'` → `$user` is the user ID; `$user.<attr>` is an XSUAA attribute (multi-valued → behaves like `IN`).
- Several grants are OR-combined: Admin has `'*'` with no where clause, so admins see everything.
- **Gotcha:** a `where` can't protect **CREATE** (no row exists yet), so check it in the handler (`req.user.attr.plant`, `req.user.is('Admin')`).
- **Gotcha we hit in the test:** after adding restrictions, carol (approver) got 404 reading alice's PR via RequisitionService. That's correct, because she must use ApprovalService. Row filters apply per service projection.
- Business rules that depend on data (approval limit, segregation of duties) stay in handlers; roles only answer "may this role do X at all".
- Keep all rules in one `access-control.cds` file, which is easy to review and keeps the services clean.

### XSUAA artefacts (`xs-security.json`)
- **Scope** (`$XSAPPNAME.Buyer`) = technical permission, checked by CAP.
- **Attribute** (`plant`) = value-based restriction, ends up in the JWT (`xs.user.attributes`).
- **Role template** = scopes + attribute references (design time, from the app).
- **Role** = an instance of a template, possibly with attribute values (e.g. "Plant 1000" from the `PlantAccess` template, value source *static*). Created in the cockpit.
- **Role collection** = bundle of roles, **assigned to users or IdP groups** in the cockpit (or via `role-collections` in xs-security.json, created on deploy).
- `$XSAPPNAME` is replaced by the real `xsappname` at deploy time (set in `mta.yaml`).
- `oauth2-configuration.redirect-uris` = allowed post-login redirect targets (approuter / Work Zone URLs).
- `cds compile srv --to xsuaa` generates scopes, attributes and templates from your `@restrict`/`@requires`. Good starting point.

### CAP vs. RAP
| CAP | RAP / ABAP |
|---|---|
| `@requires` / `@restrict grant` | Authorization object + `authorization master ( global )` in BDEF |
| `@restrict where` | DCL access control (`define role ... grant select ... where`) |
| XSUAA role template / role collection | PFCG role / business catalog / business role (Steampunk: IAM app) |
| `req.user.is('X')`, `req.user.attr` | `AUTHORITY-CHECK`, `get_global_authorizations` |

### Frequently asked (security)
- *Where is the JWT validated?* In the CAP app (`@sap/xssec`). The approuter only does login + token forwarding (`forwardAuthToken`).
- *What does the approuter do?* Login, session, token handling, routing of `/odata` to the backend destination, serving UI from the HTML5 repo, CSRF protection.
- *Why might buttons still show for users without permission?* UI annotations aren't role-aware. The server enforces 403. To hide them you'd add virtual fields (e.g. `virtual canApprove : Boolean` filled in an `after READ` handler) and use them in `@UI.Hidden` / `Core.OperationAvailable`.

---

## Phase 5 – SAP HANA Cloud (what we learned so far)

- **HANA Cloud instance** = the database (subaccount level, created in HANA Cloud Central, stops nightly on trial/free tier).
- **Instance mapping** (HANA Cloud Central → Manage Configuration) links the instance to a CF org/space. Without it, `cf create-service hana hdi-shared` fails with *"There is no database available"*.
- **HDI container** (`hana` / `hdi-shared`) = an isolated schema + technical users per app. Design-time artefacts (`.hdbtable`, `.hdbview`, `.hdbtabledata`) are deployed by the **HDI deployer** (`@sap/hdi-deploy`), which computes the delta and migrates tables.
- `cds add hana` → `@cap-js/hana` driver; in production CAP uses HANA automatically. `cds build --production` → `gen/db` (44 tables, 141 views here) = the deployer app.
- `cds deploy --to hana:<instance>` = build + service key + run the deployer **from your machine**. `cds bind` + `--profile hybrid` = local app, cloud database.
- **Corporate networks:** HANA's SQL protocol runs over TLS on port 443 but is not HTTP; TLS-inspecting proxies (Zscaler) break it. Production deployments therefore run the deployer **inside BTP** (MTA `hdb` module / CF task) or from BAS.
- SQLite vs HANA: SQLite for fast local dev/tests; HANA for real behaviour (case-sensitive collation, decimals, locking with `SELECT ... FOR UPDATE`, native features like sequences, calculation views, full-text search).

---

## Phase 6 – Remote services & destinations

### Consuming an external OData service in CAP
1. Get the API definition (EDMX) from api.sap.com → `cds import API_BUSINESS_PARTNER.edmx` → `srv/external/*.cds` with `@cds.external` + `@cds.persistence.skip` (no tables created).
2. Configure it in `cds.requires` (`kind: odata-v2`, `model`), with **per-profile credentials**:
   - development / tests: **no credentials → mocked** from `srv/external/data/*.csv` (`cds watch` does this automatically; `cds.test(dir, '--with-mocks')`)
   - `[sandbox]`: direct URL + API key (key in git-ignored `.cdsrc-private.json`)
   - `[production]`: `credentials.destination: 'S4HANA_BP'` + `path` → resolved via the **Destination service** (SAP Cloud SDK, `@sap-cloud-sdk/http-client`)
3. In the handler: `const s4 = await cds.connect.to('API_BUSINESS_PARTNER')` and `s4.run(SELECT...)`. CAP translates CQL → OData V2 (`$filter`, `substringof`, `$top`, ...).

### Patterns used
- **Delegation:** `this.on('READ', S4BusinessPartners, req => s4.run(req.query))`. The service projection is mapped back to the remote entity, so filter/paging/sort work out of the box.
- **Mash-up:** `virtual` element + `after('READ')` to enrich remote rows with local data (`importedSupplierNo`).
- **Replication:** `importAsSupplier` reads BP + address remotely and upserts the local supplier (`s4BusinessPartner` as the link). Alternatives: event-based replication via SAP Event Mesh (`BusinessPartner.Changed`), or scheduled jobs.
- OData V2 has no `$search` → `@Capabilities.SearchRestrictions.Searchable: false`.
- **Gotcha:** mocks are served from the *primary database*. With `--profile hybrid` that's HANA, where `@cds.persistence.skip` entities have no tables, so you get *"Could not find table API_BUSINESS_PARTNER_A_BUSINESSPARTNER"*. Give every non-development profile real credentials (sandbox/destination).
- **Gotcha:** `cds watch` registers mocked/served services in `~/.cds-services.json`; another local server can pick that binding up (e.g. calls to a stopped `localhost:4005` → `ECONNREFUSED`).
- `.cdsrc-private.json` must be valid JSON. An empty, unsaved file breaks config loading.

### Destination service (BTP)
- A **destination** = named connection config (URL, authentication, proxy type, extra headers) stored in the subaccount, not in code. The same code works against sandbox, dev and prod S/4 just by changing the destination.
- Important fields: `Type: HTTP`, `ProxyType: Internet` (cloud systems) or `OnPremise` (via **Cloud Connector** + Connectivity service), `Authentication`: `NoAuthentication`, `BasicAuthentication`, `OAuth2SAMLBearerAssertion` / `OAuth2JWTBearer` (**principal propagation**: the user identity flows to S/4), `OAuth2ClientCredentials` (technical user).
- Additional properties: `URL.headers.APIKey` (adds a header; used for the api.sap.com sandbox), `sap-client`, `HTML5.DynamicDestination`, `WebIDEEnabled`.
- The app needs bindings to **destination** (lite) and **xsuaa** (to fetch the destination token); on-premise also needs **connectivity**.

### CAP vs RAP
| CAP | RAP / ABAP Cloud |
|---|---|
| `cds import` + `cds.connect.to` | Service consumption model (`.srvb` consumer proxy) |
| Destination + Cloud SDK | Communication arrangement / scenario / system |
| Mocking from CSV | Test doubles (`cl_osql_test_environment`, `cl_botd_txbufdbl_bo_test_env`) |

---

## Phase 7 – Deployment (MTA, HTML5 repo, managed approuter)

### What gets deployed (`mta.yaml`)
| Module / resource | Type | Purpose |
|---|---|---|
| `p2p-cap-srv` | `nodejs` app | CAP backend (`gen/srv`), bound to XSUAA, HDI, Destination |
| `p2p-cap-db-deployer` | `hdb` | runs `@sap/hdi-deploy` **inside CF** once per deployment, then stops |
| 5 × `html5` modules | build-only | `npm run build` → UI5 preload bundle + `dist/<app>.zip` (ui5-task-zipper) |
| `p2p-cap-app-deployer` | `com.sap.application.content` | uploads the zips into the **HTML5 Application Repository** (`app-host`) |
| `p2p-cap-destinations` | `com.sap.application.content` | creates instance-level destinations for the **managed approuter** |
| `p2p-cap-auth` | `xsuaa` / `application` | from `xs-security.json`; `xsappname` + `tenant-mode` in `config` |
| `p2p-cap-db` | `hana` / `hdi-shared` | `service-name: p2p-db` reuses the existing container |
| `p2p-cap-destination` | `destination` / `lite` | hosts destinations (`srv-api`, repo, auth) + resolves `S4HANA_BP` |

- `provides: srv-api` (`srv-url: ${default-url}`) → `requires: srv-api` → `~{srv-api/srv-url}` = how modules pass URLs to each other.
- `mbt build` → `.mtar` archive (needs GNU make, available in BAS). `cf deploy x.mtar` (MultiApps plugin) → the **deploy service** creates services, pushes apps, binds, runs the deployer.
- `cf undeploy p2p-cap --delete-services` removes everything again; `cf mta p2p-cap` shows status; `cf dmol -i <id>` downloads logs.

### Managed vs standalone approuter
- **Standalone:** an own `@sap/approuter` Node app (module type `approuter.nodejs`) with its own `xs-app.json`. Full control (custom middleware, own domain), but you run, scale and patch it.
- **Managed (used here):** the approuter run by SAP inside **Work Zone / HTML5 Application Repository runtime**. You only deploy content (app zips + destinations); no app to operate. The standard for Fiori apps in Work Zone.
- Link: `manifest.json → sap.cloud.service: "p2pcap.service"` must equal `sap.cloud.service` on the destinations. That's how the managed approuter finds the XSUAA and repo for the app.
- Each app's `xs-app.json`: route `^/?odata/(.*)$` → destination `srv-api` (`ForwardAuthToken: true` → the user's JWT reaches CAP), everything else → `html5-apps-repo-rt`.
- Why **relative** OData URIs in the manifest: the app is served under `/<cloud-service>.<app-id>/...`; a relative `odata/v4/...` resolves inside that path and hits the xs-app route.

### Destinations created by the MTA
- `srv-api`: points to the CAP backend URL, `ForwardAuthToken` (+ `DynamicDestination` so the approuter can use it via `/<destination>/...`).
- `p2p-cap-html5-repository` + `p2p-cap-auth` (`OAuth2UserTokenExchange`): tell the managed approuter where the app content and the XSUAA instance are.
- Business destination `S4HANA_BP` is created **manually** in the cockpit (contains a secret API key → never in git/MTA).

### Gotchas met in this project
- `cds add …` merged `xs-security.json` twice → **duplicate scopes** (XSUAA deploy would fail). Always diff after `cds add`.
- `cds add html5-repo` generated app `package.json`s without a build (and all named `s4partners`) → added the Fiori-tools standard (`ui5-deploy.yaml` + zipper).
- `sap.cloud.service` in the manifests (`p2p`) didn't match the MTA destinations (`p2pcap.service`).
- MTA `config:` keys replace the same top-level key of `xs-security.json` (e.g. `oauth2-configuration`), so keep one source of truth.
- `npm ci` in the MTA build needs a lock file in sync with `package.json`.
- `engines.node` in `gen/srv/package.json` decides the Node version the buildpack installs. Use a range (`>=22`).
- Initial CSV data is deployed to HANA too (fine for demos; in real projects use `test/data` or `[development]`-only data).

- **"Cannot GET /" on the srv URL is correct:** the index page only exists in development; production serves only `/odata/...`, which answers **401** without a JWT. Users always come through the approuter / Work Zone.

---

## Phase 8 – SAP Build Work Zone, standard edition

### Building blocks
| Term | Meaning |
|---|---|
| **Content provider** "HTML5 Apps" | Work Zone reads all apps from the subaccount's HTML5 Application Repository (Channel Manager → refresh after every deployment) |
| **App** | one entry per `crossNavigation.inbounds` (semantic object + action → intent `#PurchaseOrder-manage`) |
| **Group** | visual block of tiles on the home page |
| **Catalog** | collection of apps for admin purposes |
| **Role** (Content Manager) | which apps a user may launch; *Everyone* = all authenticated users. Custom WZ roles appear as role collections in the cockpit |
| **Site** | the launchpad (theme, layout, pages); Site Directory → Create Site |

### How a click on a tile works
1. Tile → intent `#SupplierInvoice-manage` → the shell resolves it to app `p2p.invoices` in the HTML5 repo.
2. The **managed approuter** loads the app from `/<sap.cloud.service>.<appId>/` (here `p2pcapservice.p2pinvoices`), using the destinations `p2p-cap-html5-repository` + `p2p-cap-auth`.
3. The app calls `odata/v4/invoice/...` (relative) → `xs-app.json` route → destination `srv-api` with `ForwardAuthToken` → CAP validates the JWT → `@restrict`.

### Two layers of roles
- **Work Zone role** → may the user *see / launch* the tile?
- **XSUAA role collection** (`P2P_*`) → may the user *read / change data*? This is the real security; a visible tile without the role collection just gives 403.

### Gotchas met in this project
- **Work Zone subscription failed: "OIDC trust missing" (422):** Work Zone needs an OpenID Connect trust to SAP Cloud Identity Services (IAS). Fix: subscribe to Cloud Identity Services → Security → Trust Configuration → Establish Trust. Afterwards users log in via IAS → assign role collections to the **IAS user** (same e-mail, different identity provider).
- **Role collections from `xs-security.json` are app-managed:** you can assign users, but you can't add or remove roles in the cockpit ("+" and Delete disabled). Put attribute roles (e.g. `Plant_1000_1100` from template `PlantAccess`) into a **separate, manually created** collection. A user's roles from all collections are merged in the JWT.
- A role from a template **with attributes** has no default role; create it via *Roles → Create Role* (static values must be entered as tokens + Enter, and the wizard must be finished on step 4).
- HTML5 Applications page / Work Zone content stay empty until a launchpad service is subscribed; apps deployed **before** the subscription may need a redeploy + Channel Manager refresh.
- **Content Explorer → HTML5 Apps (0)** although the app runs via its launchpad URL: the destination service instance needs `config: { HTML5Runtime_enabled: true }` in `mta.yaml`. Work Zone only searches destination instances with this flag for apps (`cds add workzone-standard` didn't set it on the instance).
- Runtime URL of an app via the managed approuter: `https://<subdomain>.launchpad.cfapps.<region>.hana.ondemand.com/<sap.cloud.service without dots>.<app id>-<version>/`.

### Business user identity
- On BTP, `req.user.id` is the login name from the JWT (SAP ID service: the e-mail). Application data linked to users (here `Employees.userId`) must use that ID.
- Attributes (`plant`) come from roles created from the `PlantAccess` template (value source *static*) or from IdP user attributes (value source *identity provider*).
