FROM jekyll/jekyll:3.8

COPY Gemfile /srv/jekyll
COPY Gemfile.lock /srv/jekyll
RUN bundle install --frozen

RUN echo $PATH
RUN which jekyll
RUN export PATH=$PATH:/usr/gem/bin/
RUN jekyll --version

COPY . /srv/jekyll/
RUN rm /srv/jekyll/robots.txt
RUN rm /srv/jekyll/README.md
RUN rm /srv/jekyll/Makefile
RUN jekyll build --config _config_prod.yml

FROM nginx:alpine
COPY _deploy/nginx-config/nginx.conf /etc/nginx/nginx.conf
COPY _deploy/nginx-config/jekyll.conf /etc/nginx/conf.d/jekyll.conf
COPY --from=0 /srv/jekyll/_site /usr/share/nginx/html
