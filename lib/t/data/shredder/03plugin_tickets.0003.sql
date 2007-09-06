INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('33','33','33','45','45');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','33','RT::Model::Group','Create','35');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','3','AdminCc','33');
INSERT INTO "Principals"("Disabled","ObjectId","PrincipalType","id") valueS('0','33','Group','33');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('32','32','32','44','44');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','32','RT::Model::Group','Create','34');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','3','Cc','32');
INSERT INTO "Principals"("ObjectId","PrincipalType","id") valueS('32','Group','32');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('31','31','10','46','46');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('31','31','10','43','47');
INSERT INTO "GroupMembers"("GroupId","MemberId","id") valueS('31','10','10');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('31','31','31','43','43');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','31','RT::Model::Group','Create','33');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','3','Owner','31');
INSERT INTO "Principals"("ObjectId","PrincipalType","id") valueS('31','Group','31');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('30','30','30','42','42');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','30','RT::Model::Group','Create','32');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','3','Requestor','30');
INSERT INTO "Principals"("ObjectId","PrincipalType","id") valueS('30','Group','30');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','3','RT::Model::Ticket','Create','37');
INSERT INTO "Links"("Base","Creator","LocalBase","LocalTarget","Target","Type","id") valueS('fsck.com-rt://example.com/ticket/3','1','3','1','fsck.com-rt://example.com/ticket/1','MemberOf','2');
INSERT INTO "Transactions"("Creator","Field","NewValue","ObjectId","ObjectType","Type","id") valueS('1','has_member','fsck.com-rt://example.com/ticket/3','1','RT::Model::Ticket','AddLink','36');
INSERT INTO "Tickets"("Creator","Due","EffectiveId","LastUpdated","LastUpdatedBy","Owner","Queue","Resolved","Started","Starts","Status","Subject","Type","id") valueS('1','1970-01-01 00:00:00','3','2007-09-06 01:18:23','1','10','1','2007-09-06 01:18:22','2007-09-06 01:18:22','1970-01-01 00:00:00','resolved','child','ticket','3');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('25','25','25','33','33');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','25','RT::Model::Group','Create','24');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','1','AdminCc','25');
INSERT INTO "Principals"("ObjectId","PrincipalType","id") valueS('25','Group','25');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('24','24','24','32','32');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','24','RT::Model::Group','Create','23');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','1','Cc','24');
INSERT INTO "Principals"("ObjectId","PrincipalType","id") valueS('24','Group','24');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('23','23','10','34','34');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('23','23','10','31','35');
INSERT INTO "GroupMembers"("GroupId","MemberId","id") valueS('23','10','8');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('23','23','23','31','31');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','23','RT::Model::Group','Create','22');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','1','Owner','23');
INSERT INTO "Principals"("ObjectId","PrincipalType","id") valueS('23','Group','23');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('22','22','22','30','30');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','22','RT::Model::Group','Create','21');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','1','Requestor','22');
INSERT INTO "Principals"("ObjectId","PrincipalType","id") valueS('22','Group','22');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','1','RT::Model::Ticket','Create','25');
INSERT INTO "Transactions"("Creator","Field","NewValue","ObjectId","ObjectType","Type","id") valueS('1','has_member','fsck.com-rt://example.com/ticket/2','1','RT::Model::Ticket','AddLink','30');
INSERT INTO "Links"("Base","Creator","LocalBase","LocalTarget","Target","Type","id") valueS('fsck.com-rt://example.com/ticket/2','1','2','1','fsck.com-rt://example.com/ticket/1','MemberOf','1');
INSERT INTO "Tickets"("Creator","Due","EffectiveId","LastUpdated","LastUpdatedBy","Owner","Queue","Resolved","Started","Starts","Status","Subject","Type","id") valueS('1','1970-01-01 00:00:00','1','2007-09-06 01:18:23','1','10','1','2007-09-06 01:18:22','2007-09-06 01:18:22','1970-01-01 00:00:00','resolved','parent','ticket','1');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('29','29','29','39','39');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','29','RT::Model::Group','Create','29');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','2','AdminCc','29');
INSERT INTO "Principals"("ObjectId","PrincipalType","id") valueS('29','Group','29');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('28','28','28','38','38');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','28','RT::Model::Group','Create','28');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','2','Cc','28');
INSERT INTO "Principals"("ObjectId","PrincipalType","id") valueS('28','Group','28');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('27','27','10','40','40');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('27','27','10','37','41');
INSERT INTO "GroupMembers"("GroupId","MemberId","id") valueS('27','10','9');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('27','27','27','37','37');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','27','RT::Model::Group','Create','27');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','2','Owner','27');
INSERT INTO "Principals"("ObjectId","PrincipalType","id") valueS('27','Group','27');
INSERT INTO "CachedGroupMembers"("GroupId","ImmediateParentId","MemberId","Via","id") valueS('26','26','26','36','36');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','26','RT::Model::Group','Create','26');
INSERT INTO "Groups"("Domain","Instance","Type","id") valueS('RT::Model::Ticket-Role','2','Requestor','26');
INSERT INTO "Principals"("ObjectId","PrincipalType","id") valueS('26','Group','26');
INSERT INTO "Transactions"("Creator","ObjectId","ObjectType","Type","id") valueS('1','2','RT::Model::Ticket','Create','31');
INSERT INTO "Tickets"("Creator","Due","EffectiveId","LastUpdated","LastUpdatedBy","Owner","Queue","Resolved","Started","Starts","Status","Subject","Type","id") valueS('1','1970-01-01 00:00:00','2','2007-09-06 01:18:22','1','10','1','1970-01-01 00:00:00','1970-01-01 00:00:00','1970-01-01 00:00:00','new','child','ticket','2');