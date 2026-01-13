{
  description = "macroquad wasm web bundle";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    fenix.url = "github:nix-community/fenix";
    crane.url = "github:ipetkov/crane";
  };

  outputs = { self, nixpkgs, flake-utils, fenix, crane }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        rustToolchain = fenix.packages.${system}.combine [
          fenix.packages.${system}.stable.rustc
          fenix.packages.${system}.stable.cargo
          fenix.packages.${system}.stable.clippy
          fenix.packages.${system}.stable.rustfmt
          fenix.packages.${system}.targets.wasm32-unknown-unknown.stable.rust-std
        ];


        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        # Prefetch/vendor Cargo dependencies (offline builds)
        cargoArtifacts = craneLib.buildDepsOnly {
          src = self;
        };

        # Helper: render html template using config.env and envsubst
        renderHtml = ''
          TEMPLATE="${self}/html/index.html"
          CONFIG="${self}/config.env"

          # Export vars from config.env
          set -a
          # shellcheck disable=SC1090
          source "$CONFIG"
          set +a

          # Only substitute variables actually used in the template
          VARS=$(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$TEMPLATE" | sort -u | tr '\n' ' ')
          envsubst "$VARS" < "$TEMPLATE" > "$out/index.html"
        '';
      in
      {
        packages.default = self.packages.${system}.web;

        packages.web = craneLib.buildPackage {
          src = self;
          inherit cargoArtifacts;

          # We build wasm; macroquad typically doesn't need wasm-bindgen.
          cargoExtraArgs = "--target wasm32-unknown-unknown";
          doCheck = false;

          nativeBuildInputs = [
            pkgs.gettext   # envsubst
            pkgs.gnugrep
            pkgs.coreutils
            pkgs.esbuild
            pkgs.binaryen
          ];

          installPhase = ''
            runHook preInstall

            mkdir -p "$out"

            WASM_DIR="target/wasm32-unknown-unknown/release"
            if [ ! -d "$WASM_DIR" ]; then
              echo "ERROR: expected wasm output dir missing: $WASM_DIR" >&2
              exit 1
            fi

            set -a
            source "${self}/config.env"
            set +a

            cp "$WASM_DIR/$WASM_FILE" "$out/"
            wasm-opt -O3 "$out/$WASM_FILE" -o "$out/$WASM_FILE"

            #Minify and save to result
            esbuild js/"$MQ_JS_BUNDLE" \
            --minify \
            --bundle=false \
            --outfile="$out/$MQ_JS_BUNDLE"

            # Render index.html from html/index.html using config.env
            ${renderHtml}

            runHook postInstall
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = [
            rustToolchain
            pkgs.rust-analyzer
            pkgs.gettext
            pkgs.jq
          ];
        };
      });
}

