# README

Footlight Condenser Server used with Footlight **Wringer Server**, Footlight **Code Snippet Server**, and Footlight **Console Servers** (multiple skins)

Distillator migration fetch modes, replay behavior, refresh UI guarding, and rollback notes are documented in [docs/distillator_migration.md](docs/distillator_migration.md).


# Local Development
To setup for local development clone this repo.

> `yarn intalll`
> `yarn build`

# Tests

To run tests use:

> `Rails test`

## Fast Distillator/Wringer unit preflight

Use this while working on the Distillator/Wringer replacement seam:

```bash
DISABLE_SPRING=1 bin/rails test:distillator_fast
```

This command runs fast unit tests only. It intentionally excludes VCR-backed scrape integration tests and full export/graph coverage.

For recorded scrape behavior:

```bash
DISABLE_SPRING=1 bundle exec rails test test/integration/statements_helper_scrape_integration_test.rb
```

Before merging release-sensitive changes, run:

```bash
DISABLE_SPRING=1 bin/rails test
```

Optional slow-test reporting:

```bash
REPORT_SLOW_TESTS=1 SLOW_TEST_THRESHOLD=1.0 DISABLE_SPRING=1 bin/rails test
```

Note: The PRODUCTION server initializes with a fresh copy of the artsdata.ca database for performance reasons (code snippet related.) The DEV and TEST servers initialize the artsdata.ca database with a static local dump of the artsdata.ca triple store. To update the static dump of the triple store (beware tests may fail if data changes) uncomment the following line in config/initializers/artsdata_graph.rb: 

> `File.open("artsdata-dump.nt", "w") {|f| f << @@artsdata_graph.dump(:ntriples)}`


# Code Snippet
This server reponds to the Code Snippet Server stored in AWS Lamda Serverless Backend. The Footlight Code Snippet is included on client web pages to inject JSON-LD from Footlight augmented by artsdata.ca.

The code snippet is:

```
<script>
  (function(i,s,o,g,r,a,m){a=s.createElement(o),m=s.getElementsByTagName(o)[0];a.async=1;a.src= g+'?url='+i.location;m.parentNode.insertBefore(a,m)})(window,document,'script', 'https://graph.culturecreates.com/footlight/v2/event-markup');
</script>
```

The Amazon API Gateway is used to forward requests to the Code Snippet Server, cache requests for 1 hour, and format the reponse returned to the calling webpage like this:
```
<script>
 (function() {
    var data = {
        // JSON-LD Response from Code Snippet Server
        "@context": { "@vocab": "http://schema.org/"},
        ...
    };
    var script = document.createElement('script');
    script.type = "application/ld+json";
    script.innerHTML = JSON.stringify(data);
    document.getElementsByTagName('head')[0].appendChild(script);
})(document);
<script>
```

For the Javascript code of the Footlight Code Snippet Server see lib/assets/footlight-code-snippet-server.js.  The Code Snippet Server checks that the calling webpage url fits one of the listed patterns (i.e. "spec.qc.ca" : ["/spectacle/","/artiste/"]) before calling the Footlight Condenser to obtain the JSON-LD.

# Download production database
To develop with fresh data, download the production database to the dev environment.

> `heroku pg:backups:capture`

> `heroku pg:backups:download`

> `mv latest.dump.1 latest.dump`

> `./reload_db.sh`


# AWS S3 credentials

Load environment credentials for ACCESS_KEY_ID and SECRET_ACCESS_KEY to access S3. For DEV keep them in a local file called .aws_keys but NEVER check them into source control.
