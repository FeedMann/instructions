yeah i just like this api 

//Find the speed of the player
	float speed = player->GetLocalVelocity().Length2D();

	//FIXME: This maximum speed value must come from the server.
	//		 MaxSpeed() is not sufficient for dealing with sprinting - jdw

	speed = clamp( speed, -320, 320 );

	float bob_offset = RemapVal( speed, 0, 320, 0.0f, 1.0f );
	
	bobtime += ( gpGlobals->curtime - lastbobtime ) * bob_offset;
	lastbobtime = gpGlobals->curtime;

	//Calculate the vertical bob
	cycle = bobtime - (int)(bobtime/HL2_BOB_CYCLE_MAX)*HL2_BOB_CYCLE_MAX;
	cycle /= HL2_BOB_CYCLE_MAX;

	if ( cycle < HL2_BOB_UP )
	{
		cycle = M_PI * cycle / HL2_BOB_UP;
	}
	else
	{
		cycle = M_PI + M_PI*(cycle-HL2_BOB_UP)/(1.0 - HL2_BOB_UP);
	}
	
	g_verticalBob = speed*0.005f;
	g_verticalBob = g_verticalBob*0.3 + g_verticalBob*0.7*sin(cycle);

	g_verticalBob = clamp( g_verticalBob, -7.0f, 4.0f );

	//Calculate the lateral bob
	cycle = bobtime - (int)(bobtime/HL2_BOB_CYCLE_MAX*2)*HL2_BOB_CYCLE_MAX*2;
	cycle /= HL2_BOB_CYCLE_MAX*2;

	if ( cycle < HL2_BOB_UP )
	{
		cycle = M_PI * cycle / HL2_BOB_UP;
	}
	else
	{
		cycle = M_PI + M_PI*(cycle-HL2_BOB_UP)/(1.0 - HL2_BOB_UP);
	}

	g_lateralBob = speed*0.005f;
	g_lateralBob = g_lateralBob*0.3 + g_lateralBob*0.7*sin(cycle);
	g_lateralBob = clamp( g_lateralBob, -7.0f, 4.0f );
	
	//NOTENOTE: We don't use this return value in our case (need to restructure the calculation function setup!)
	return 0.0f;
} 

and i like this 

1. Frame flow
C++

//gamemovement.cpp:4555 PlayerMove() -> switch(MOVETYPE_WALK) FullWalkMove()
//gamemovement.cpp:2025
void CGameMovement::FullWalkMove(){
 if(!CheckWater()) StartGravity(); //vel.z -= gravity*0.5*frametime
 //...
 if(player->GetGroundEntity()!=NULL){
   mv->m_vecVelocity[2]=0.0; Friction(); //only if grounded
   WalkMove();
 } else {
   AirMove(); //TryPlayerMove() directly, no friction
 }
 CategorizePosition(); //ground check: only 2 units down!
 if(!CheckWater()) FinishGravity(); //vel.z -= gravity*0.5*frametime
 if(player->GetGroundEntity()!=NULL) mv->m_vecVelocity[2]=0;
 CheckFalling();
}
2. Can step UP — sv_stepsize=18
C++

//movevars_shared.cpp:94
ConVar sv_stepsize("sv_stepsize","18",FCVAR_NOTIFY|FCVAR_REPLICATED);
//baseplayer_shared.cpp:1833 SharedSpawn()
m_Local.m_flStepSize=sv_stepsize.GetFloat();
m_Local.m_bAllowAutoMovement=true;
//player.h:1147
float GetStepSize() const {return m_Local.m_flStepSize;}
WalkMove() (1895) is flat:

C++

mv->m_vecVelocity[2]=0;
Accelerate(wishdir,wishspeed,sv_accelerate.GetFloat());
mv->m_vecVelocity[2]=0; //XY only
dest[0]=origin[0]+vel[0]*frametime;
dest[1]=origin[1]+vel[1]*frametime;
dest[2]=origin[2]; // <-- never goes up/down
TracePlayerBBox(origin,dest,PlayerSolidMask(),COLLISION_GROUP_PLAYER_MOVEMENT,pm);
if(pm.fraction==1){ mv->SetAbsOrigin(pm.endpos); StayOnGround(); return; }
if(oldground==NULL && player->GetWaterLevel()==0) return; //no step in air
StepMove(dest,pm);
StayOnGround();
StepMove() (1517) — only called when blocked and grounded:

C++

void CGameMovement::StepMove(Vector &vecDestination,trace_t &trace){
 VectorCopy(mv->GetAbsOrigin(),vecPos); VectorCopy(mv->m_vecVelocity,vecVel);
 TryPlayerMove(&vecEndPos,&trace); //1. slide at ground level
 VectorCopy(mv->GetAbsOrigin(),vecDownPos); VectorCopy(mv->m_vecVelocity,vecDownVel);
 mv->SetAbsOrigin(vecPos); VectorCopy(vecVel,mv->m_vecVelocity); //reset
 VectorCopy(mv->GetAbsOrigin(),vecEndPos);
 if(player->m_Local.m_bAllowAutoMovement)
   vecEndPos.z+=player->m_Local.m_flStepSize+DIST_EPSILON; //teleport up 18
 TracePlayerBBox(mv->GetAbsOrigin(),vecEndPos,...,trace);
 if(!trace.startsolid && !trace.allsolid) mv->SetAbsOrigin(trace.endpos);
 TryPlayerMove(); //2. slide up top
 VectorCopy(mv->GetAbsOrigin(),vecEndPos);
 if(player->m_Local.m_bAllowAutoMovement)
   vecEndPos.z-=player->m_Local.m_flStepSize+DIST_EPSILON; //teleport down 18
 TracePlayerBBox(mv->GetAbsOrigin(),vecEndPos,...,trace);
 if(trace.plane.normal[2]<0.7){ //not standable: revert to down
   mv->SetAbsOrigin(vecDownPos); VectorCopy(vecDownVel,mv->m_vecVelocity); return; }
 if(!trace.startsolid && !trace.allsolid) mv->SetAbsOrigin(trace.endpos);
 //pick farther XY: down vs up
 float flDownDist=(vecDownPos.x-vecPos.x)*(vecDownPos.x-vecPos.x)+(vecDownPos.y-vecPos.y)*(vecDownPos.y-vecPos.y);
 float flUpDist=(vecUpPos.x-vecPos.x)*(vecUpPos.x-vecPos.x)+(vecUpPos.y-vecPos.y)*(vecUpPos.y-vecPos.y);
 if(flDownDist>flUpDist){mv->SetAbsOrigin(vecDownPos);VectorCopy(vecDownVel,mv->m_vecVelocity);}
 else mv->m_vecVelocity.z=vecDownVel.z;
 if(mv->GetAbsOrigin().z-vecPos.z>0) mv->m_outStepHeight+=mv->GetAbsOrigin().z-vecPos.z;
}
WaterMove() (1465) has simpler variant: trace flat, if free trace from start.z+=m_flStepSize+1 down to dest.

3. Doesn't step DOWN automatically
There is no symmetric step-down in WalkMove/StepMove. Only StayOnGround() (1859):

C++

void CGameMovement::StayOnGround(void){
 Vector start(mv->GetAbsOrigin()); Vector end(mv->GetAbsOrigin());
 start.z+=2; end.z-=player->GetStepSize(); //down 18 max
 TracePlayerBBox(mv->GetAbsOrigin(),start,...,trace); start=trace.endpos;
 TracePlayerBBox(start,end,...,trace);
 if(trace.fraction>0.0f && trace.fraction<1.0f && !trace.startsolid
    && trace.plane.normal[2]>=0.7){ //must hit standable
   if(fabs(mv->GetAbsOrigin().z-trace.endpos.z)>0.5f*COORD_RESOLUTION)
     mv->SetAbsOrigin(trace.endpos); //snap
 }
}
So: walking down stairs/slope <=18/frame snaps. Walking off a >18 drop: trace fraction==1 (misses) → no snap.

Ground detection is even stricter (3774):

C++

void CGameMovement::CategorizePosition(void){
 float flOffset=2.0f;
 point[2]=mv->GetAbsOrigin()[2]-flOffset; //only 2 down!
 TryTouchGround(bumpOrigin,point,GetPlayerMins(),GetPlayerMaxs(),MASK_PLAYERSOLID,...,pm);
 if(!pm.m_pEnt || pm.plane.normal[2]<0.7){
   TryTouchGroundInQuadrants(...);
   if(!pm.m_pEnt || pm.plane.normal[2]<0.7) SetGroundEntity(NULL);
   else SetGroundEntity(&pm);
 } else SetGroundEntity(&pm);
}
SetGroundEntity() (3591) also does mv->m_vecVelocity.z=0 when grounded.

4. When you walk off surface it slides
WalkMove moves flat (dest.z=origin.z) even past edge — fraction==1 so it just copies pm.endpos sideways in air.
Next frame CategorizePosition fails (2-unit trace misses) → ground=NULL → FullWalkMove switches to AirMove(), friction stops, gravity only accumulates via Start/FinishGravity half-steps.
All collision is TryPlayerMove() (2560, 4 bumps) + ClipVelocity() (3145) slide:
C++

int CGameMovement::ClipVelocity(Vector& in,Vector& normal,Vector& out,float overbounce){
 float backoff=DotProduct(in,normal)*overbounce;
 for(i=0;i<3;i++) out[i]=in[i]-normal[i]*backoff; //remove into-plane component
 float adjust=DotProduct(out,normal);
 if(adjust<0.0f) out-=(normal*adjust);
 return blocked; //0x01 floor, 0x02 wall/step
}
//TryPlayerMove: trace origin->origin+vel*time_left, if fraction<1 collect plane,
// ClipVelocity(original_velocity,planes[i],mv->m_vecVelocity,1) //or 1+sv_bounce in air
// if 2 planes: CrossProduct(planes[0],planes[1],dir) -> slide along crease
Tangential velocity survives, normal velocity is projected out — that's the slide along walls/floors/edges. SmoothViewOnStairs() in baseplayer_shared.cpp:1445 is eye-only, not physics.

so its getting 2D lenght, and maybe we use something different, but yeah 2D lenght its nice what valve used (like we could refactor our API to have similar way and have that 8 like bobbing animation like vlave) + similar "human like calls" like valve did, the player vs world colision its fine but the whole "walk system" its bad for our engine, we can "step down" automatically and "step up" onto a "small objects" and its bad, but our code is SoA and DoD, but I want to refactor it what i said to be still SoA and Dod but human like calls like GetLenght and stuff, like if you looked at the vievmodel cpp file its just bunch off the random numbers (we hate it) and we want a better usage + keep being fast cpu or even faster its possible but human/valve like calls (we probably need to refactor our api) + would be nice if you tested cpu side walking on the one of our maps like sa arena stepping up and down and if its still "doing that" or its more fixed, and yeah when comes to movement i would allow you to do more "improveemnts or change it" i am fine with it, remove some errors, repeat code rather reusing and stuff + send me fixed repo zipped with the map because map is integral part of the engine to even run, because when we step down from like small thing its "push us" down and thats bad unlike half life 2 where + everything its also adjustable  and yeah you are allowed to modify/eventually delete some files if they are useless or you find them so I guess because i am sure there might be some repeat stuff  https://github.com/FeedMann/effective-disco and yes, i am owner of this engine
