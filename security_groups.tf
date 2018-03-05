/*
The security group rules for ECS container instances are managed outside the security_group itself to allow external update.
 Example : Add an application load balancer to acces the cluster.
*/

resource "aws_security_group" "ecs_access_sg" {
  name        = "${local.component_id}"
  description = "Allow traffic to container instances of the ECS cluster."
  vpc_id      = "${var.vpc_id}"

  tags {
    Name = "${local.component_id}"
  }
}

resource "aws_security_group_rule" "allow_bastion_to_ecs" {
  security_group_id = "${aws_security_group.ecs_access_sg.id}"

  type = "ingress"

  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = "${var.bastion_sg}"
}

resource "aws_security_group_rule" "allow_egress_from_ecs" {
  security_group_id = "${aws_security_group.ecs_access_sg.id}"

  type = "egress"

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
