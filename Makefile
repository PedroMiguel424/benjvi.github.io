
.PHONY: serve-dev serve-drafts publish-image publish-solar-image

serve-dev:
	bundle exec jekyll serve --config _config_dev.yml

serve-drafts:
	bundle exec jekyll serve --config _config_dev.yml --drafts

TAG := $(shell git rev-parse --short=8 HEAD)
publish-image:
	docker buildx build --platform linux/arm64 . -f _deploy/Dockerfile-mains -t "benjvi/blog-arm:$(TAG)" --push

publish-solar-image:
	docker buildx build --platform linux/arm/v6 . -f Dockerfile-solar -t benjvi/blog-solar --push
