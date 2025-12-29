run:
	hugo server -D

post:
	hugo new "post/$$(date +\%Y-\%m-\%d)-auto/index.md"