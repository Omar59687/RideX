-- A02 read-only gate/ACL probes. Does not enable Card or call a financial command.
begin;
create extension if not exists pgtap with schema extensions;
select plan(4);
select ok(not has_function_privilege('authenticated','public.backend_card_matching_enabled()','execute'),'Rider cannot inspect gate');
select ok(not has_table_privilege('service_role','private.p8_card_matching_gate','update'),'service cannot enable gate');
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select is(public.backend_card_matching_enabled(),false,'gate remains off');
reset role;
select ok(not has_function_privilege('authenticated','public.backend_prepare_card_command(uuid,uuid,uuid,integer,integer,text,text,text)','execute'),'clients cannot call trusted command');
select * from finish();
rollback;
