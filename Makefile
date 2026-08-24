.PHONY: all setup run stop clean test load-test segfault-test status

all: setup

setup: rust-build crystal-build rails-setup
	@echo "✅ Setup selesai. Jalankan 'make run' untuk memulai."

rust-build:
	@echo "🦀 Membangun Rust Parser..."
	cd parser && cargo build --release

crystal-build:
	@echo "💎 Membangun Crystal Worker..."
	cd worker && shards install && crystal build src/kalubampa_worker.cr --release -o bin/kalubampa_worker

rails-setup:
	@echo "🚂 Menyiapkan Rails Dashboard..."
	cd dashboard && bundle install && rails db:prepare

run:
	@echo "🚀 Memulai Kalubampa (Podman Compose)..."
	podman-compose -f podman/podman-compose.yml up -d

stop:
	@echo "🛑 Menghentikan Kalubampa..."
	podman-compose -f podman/podman-compose.yml down

status:
	@echo "📊 Status Container:"
	podman-compose -f podman/podman-compose.yml ps

logs:
	podman-compose -f podman/podman-compose.yml logs -f

logs-worker:
	podman-compose -f podman/podman-compose.yml logs -f worker

logs-dashboard:
	podman-compose -f podman/podman-compose.yml logs -f dashboard

test:
	@echo "🧪 Menjalankan Unit Tests (Rust & Crystal)..."
	cd parser && cargo test
	cd worker && crystal spec

load-test:
	@echo "🔥 Memulai Load Test (10.000 URL)..."
	./scripts/load_test.rb

segfault-test:
	@echo "🛡️ Memulai Segfault Isolation Test..."
	./scripts/segfault_test.rb

clean: stop
	@echo "🧹 Membersihkan build artifacts..."
	cd parser && cargo clean
	rm -rf worker/bin/
	rm -rf worker/lib/
	@echo "✅ Bersih!"
