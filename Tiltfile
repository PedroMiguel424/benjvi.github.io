allow_k8s_contexts('rpi')
custom_build(
  'benjvi/blog-arm-dev',
  'docker buildx build  --platform linux/arm64 . -f _deploy/Dockerfile-dev -t $EXPECTED_REF --push',
  deps=['.'],
  skips_local_docker=True,
  ignore=['_drafts','_posts'],
  live_update=[
    sync('./_site', '/usr/share/nginx/html')
  ]
)

k8s_yaml('_deploy/k8s-dev/blog.yml')
