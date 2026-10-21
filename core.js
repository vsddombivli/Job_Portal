export const SKILLS = ['Tally','Excel','GST','Accounting','Bookkeeping','Sales','Customer service','Communication','Data entry','MS Office','Administration','Inventory','Payroll','Recruitment','Teaching','English','Hindi','Gujarati','JavaScript','HTML','CSS','React','Python','SQL','Java','Digital marketing','Social media','Graphic design','AutoCAD','Banking','Finance','Logistics','Operations','Retail','Purchase','Typing','Power BI','SAP','Word','Email','HR','Taxation'];
const aliases={'ms excel':'excel','microsoft excel':'excel','tally prime':'tally','tally erp':'tally','accounts':'accounting','customer support':'customer service','human resources':'hr','js':'javascript'};
export const normal = s => String(s||'').trim().toLowerCase().replace(/\s+/g,' ');
export const terms = s => [...new Set((Array.isArray(s)?s:String(s||'').split(',')).map(normal).filter(Boolean).map(x=>aliases[x]||x))];
export const esc = s => String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function extractResume(text){
 const clean=text.slice(0,150000);const low=normal(clean);
 const found=SKILLS.filter(skill=>new RegExp('(^|[^a-z0-9])'+skill.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'([^a-z0-9]|$)','i').test(clean));
 for(const [alias,canonical] of Object.entries(aliases)){if(low.includes(alias)&&!found.some(x=>normal(x)===canonical))found.push(SKILLS.find(x=>normal(x)===canonical)||canonical);}
 return {skills:found,email:clean.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i)?.[0]||'',phone:clean.match(/(?:\+91[\s-]?)?[6-9](?:[\s-]?\d){9}\b/)?.[0]?.replace(/[\s-]/g,'')||''};
}
export function matchJob(profile,job){
 const skills=terms(profile.skills);const wanted=terms(job.skills);const common=wanted.filter(x=>skills.includes(x));
 const reasons=[];let total=0,available=0;
 const part=(weight,score)=>{available+=weight;total+=weight*score;};
 if(wanted.length){part(40,common.length/wanted.length);if(common.length)reasons.push('skills');}
 if(profile.roles||profile.employment_type){let n=0,d=0;
  if(profile.roles&&job.category){const role=terms(profile.roles).some(x=>normal(job.category).includes(x)||normal(job.title).includes(x));n+=role?20:0;d+=20;if(role)reasons.push('role');}
  if(profile.employment_type&&job.employment_type){const type=profile.employment_type===job.employment_type;n+=type?5:0;d+=5;if(type)reasons.push('employment type');}
  if(d)part(25,n/d);
 }
 if(profile.cities||profile.work_mode){let n=0,d=0;
  if(profile.cities){const loc=terms(profile.cities).some(x=>normal(job.city).includes(x))||job.work_mode==='Remote'||profile.relocate;n+=loc?10:0;d+=10;if(loc)reasons.push('location');}
  if(profile.work_mode&&profile.work_mode!=='Any'){const mode=profile.work_mode===job.work_mode;n+=mode?5:0;d+=5;if(mode)reasons.push('work mode');}
  if(d)part(15,n/d);
 }
 if(profile.experience!==null&&profile.experience!==undefined&&profile.experience!==''){const years=Number(profile.experience);const exp=years>=Number(job.experience_min||0)&&(job.experience_max==null||years<=Number(job.experience_max));part(10,exp?1:0);if(exp)reasons.push('experience');}
 if(Number(profile.expected_ctc)>0&&Number(job.salary_max)>0){const pay=Number(job.salary_max)>=Number(profile.expected_ctc);part(10,pay?1:0);if(pay)reasons.push('salary');}
 const missing=terms(job.mandatory_skills).filter(x=>!skills.includes(x));
 return {score:available?Math.round(total/available*100):0,reasons,eligible:missing.length===0,missing};
}
export function isOpen(job,today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())){return job.status==='published'&&(!job.closes_on||job.closes_on>=today);}
export function completion(p){const keys=['full_name','phone','city','roles','skills','employment_status','experience','cities'];return Math.round(keys.filter(k=>Array.isArray(p[k])?p[k].length:p[k]!==null&&p[k]!==undefined&&p[k]!=='').length/keys.length*100);}
export function validateProfile(p){if(!String(p.full_name||'').trim())throw Error('Please enter your name.');if(!/^\+?[0-9]{10,15}$/.test(p.phone||''))throw Error('Enter a valid mobile number, including country code if needed.');if(!p.roles?.trim()||!p.skills?.length||!p.cities?.trim())throw Error('Add preferred roles, at least one skill, and preferred locations.');for(const k of ['experience','current_ctc','expected_ctc'])if(p[k]!=null&&(!Number.isFinite(Number(p[k]))||Number(p[k])<0))throw Error('Experience and salary cannot be negative.');}
export function validateJob(j){for(const k of ['title','company','city','category','description'])if(!String(j[k]||'').trim())throw Error('Complete all required job fields.');if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(j.recipient_email||''))throw Error('Enter a valid employer email.');if(!j.source_verified)throw Error('Verify the employer before saving.');if(Number(j.experience_min)<0||(j.experience_max!=null&&Number(j.experience_max)<Number(j.experience_min)))throw Error('Check the experience range.');if(j.salary_min!=null&&j.salary_max!=null&&Number(j.salary_min)>Number(j.salary_max))throw Error('Minimum salary cannot exceed maximum salary.');}
