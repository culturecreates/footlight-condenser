# Runtime versions

Condenser uses Ruby 3.4.12 and Node.js 26. The Gemfile reads `.ruby-version`,
and `Gemfile.lock` records the installed Ruby version. Update the version file
and run `bundle update --ruby` with that Ruby installed when changing Ruby.

`.node-version` records the verified local Node patch (26.13.1). `package.json`
requires the Node 26 line and Yarn 1.22.22. `yarn.lock` retains the existing package
versions. Esbuild is a dependency because Rails compiles assets after Heroku's
Node buildpack may have pruned development dependencies.

## Heroku staging

Use the classic Node.js buildpack before Ruby so that the configured Node and
Yarn versions apply instead of Ruby's changing fallback versions:

```sh
heroku buildpacks:add --index 1 heroku/nodejs --app footlight-condenser-test
heroku buildpacks --app footlight-condenser-test
```

The expected order is `heroku/nodejs`, then `heroku/ruby`. Redeploy after changing
buildpacks or runtime files. The deployed app's buildpack configuration is managed
on Heroku; committing the version files alone does not change that configuration.

`bin/bundle` is intentionally absent: invoke `bundle` directly. This follows the
Ruby buildpack's warning about the binstub interfering with Bundler cleanup.

## Verification

Check the installed runtimes and locked dependencies, then build assets and run the
existing regression suites:

```sh
ruby --version
node --version
yarn --version
bundle check
yarn install --frozen-lockfile --production=true
yarn build
bundle exec rake assets:precompile
bundle exec rake test:distillator_fast
```

Production-dependency installation is included so the asset build remains valid
after development dependencies are pruned. Ruby 4 is a separate compatibility
upgrade; this update stays on the existing Ruby 3.4 series.

## Staging build improvements

Puma is locked to 7.2.3, within the 7.x line and above Heroku's recommended
minimum of 7.0.3. The existing zero-worker, five-thread default configuration and
Sidekiq concurrency are unchanged. RuboCop and its extensions are development/test
dependencies; `ostruct` is an explicit runtime dependency for RDF.

With the Node-then-Ruby buildpack order above, Node installs the JavaScript
dependencies and `heroku-postbuild` defers compilation to Rails. The Ruby
buildpack's `assets:precompile` then runs jsbundling and Sprockets together. This
removes the extra esbuild invocation while retaining the normal dependency check
in jsbundling. Local `yarn build` and Rails asset compilation still work normally.

Do **not** set `SKIP_JS_BUILD` with this arrangement: Rails owns the JavaScript
build. An older skip setting must be unset before deploying this patch. No new
Heroku config variable is required.

For the first staging deploy, verify:

- The Node phase prints the deferral message, and the Ruby phase runs `yarn build`
  once before writing fingerprinted assets.
- The build reports Puma 7.2.3 and no RDF warning about an undeclared `ostruct`.
- Web and worker dynos start successfully; the website list, DSL Library, and
  transition pages load with JavaScript and CSS after a hard reload.

This patch adds no release-phase migration command. Database migrations remain a
separate operator action; a successful build does not establish that the deployed
schema is current. It does not change application data, schedules, rollout modes,
or Heroku configuration. Deploy the staging branch before considering production.

References: [Heroku Ruby support](https://devcenter.heroku.com/articles/ruby-support-reference),
[Node.js support](https://devcenter.heroku.com/articles/nodejs-support),
[classic Node.js builds](https://devcenter.heroku.com/articles/nodejs-classic-buildpack-builds),
[Puma on Heroku](https://devcenter.heroku.com/articles/deploying-rails-applications-with-the-puma-web-server),
[Bundler Ruby directive](https://guides.rubygems.org/gemfile_ruby/).
