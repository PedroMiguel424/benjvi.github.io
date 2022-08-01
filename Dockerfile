FROM benjvi:blog-builder as builder
COPY . /srv/jekyll/
RUN rm /srv/jekyll/robots.txt
RUN rm /srv/jekyll/README.md
RUN rm /srv/jekyll/Makefile
RUN jekyll build --config _config_prod.yml

FROM nginx:alpine
COPY _deploy/nginx-config/nginx.conf /etc/nginx/nginx.conf
COPY _deploy/nginx-config/jekyll.conf /etc/nginx/conf.d/jekyll.conf
COPY --from=builder /srv/jekyll/_site /usr/share/nginx/html
