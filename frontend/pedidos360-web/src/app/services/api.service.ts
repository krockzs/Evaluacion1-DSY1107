import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../environments/environment';
import { OtDetail, OtResumen, UserClaims } from '../models';
@Injectable({providedIn:'root'}) export class ApiService {
  private readonly base=`${environment.bffUrl}/api`;
  constructor(private http:HttpClient){}
  me():Observable<UserClaims>{return this.http.get<UserClaims>(`${this.base}/me`);}
  ots():Observable<OtResumen[]>{return this.http.get<OtResumen[]>(`${this.base}/ots`);}
  ot(id:string):Observable<OtDetail>{return this.http.get<OtDetail>(`${this.base}/ots/${id}`);}
  createOt(body:any):Observable<any>{return this.http.post(`${this.base}/ots`,body);}
  updateOt(id:string,body:any):Observable<any>{return this.http.put(`${this.base}/ots/${id}`,body);}
  deleteOt(id:string):Observable<void>{return this.http.delete<void>(`${this.base}/ots/${id}`);}
  addItem(id:string,body:any):Observable<any>{return this.http.post(`${this.base}/ots/${id}/items`,body);}
  deleteItem(id:string,itemId:number):Observable<void>{return this.http.delete<void>(`${this.base}/ots/${id}/items/${itemId}`);}
}
