FROM nginx:alpine

LABEL maintainer="Farhan Shaikh"
LABEL description="Hospital Management System"

COPY application/ /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]