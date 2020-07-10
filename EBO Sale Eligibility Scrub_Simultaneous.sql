--WORKING TO ADD VA REFI TO ELIGIBILITY SCRUB
--Pull all FHA loans 90 days delinquent in GNMA pools, excluding Constellation/Pisces/Cypress and Liquidation investor I
/*
Creating a script as part of the automation project for EBOs
*/
Declare @MEPeriod INT
SET @MEPeriod = (SELECT LEFT(convert(varchar, DATEADD(MONTH, -1, GETDATE()), 112),6))

--This section automatically calculates the DateKey for the end of the previous month
DECLARE @DateKey INT
SET @DateKey = (select CONVERT(varchar,dateadd(d,-(day(getdate())),getdate()),112))

--This section calculates FC Sale data cutoff as 2 months prior at 1st of month
Declare @Cutoff_1stOfMonth_Prev2Months date
SET @Cutoff_1stOfMonth_Prev2Months = (select dateadd(MONTH,-2,(CONVERT(date,dateadd(d,-(day(getdate())) + 1,getdate()),112))));

With cte_eboscrub as (

select 
LM.LoanId
,LM.TradeId as TradeCollateral
,LM.LoTypeId
,Case	WHEN lm.LoTypeId = '1' THEN 'FHA'
		WHEN lm.LoTypeId = '2' THEN 'VA'
		WHEN lm.LoTypeId = '9' THEN 'USDA'
		
	End as LoanType
,cast(LM.RunDt as date) as RunDt
,LS.LoanStatusDesc as LoanStatus
,LM.CurrentPrincipalBalanceAmt
,LM.CurrentInterestRate
,LM.FirstServiceFeeRt as SFee
,LM.FHA_DebentureRt as DebentureRate
,LM.ARMFlag
,LM.LossMitStatusCodeid
,LM.LossMitTemplateId
,LM.LossMitDenialReasonCodeid
,MM.StatusCurrent
,case 
	--when LM.NativeAmericanHousingFlag = '1' then 'NativeAmericanHousing'
	when (lm.LossMitStatusCodeid in ('C') and lm.LossMitTemplateId like '%mod%' and  DATEDIFF("d",mm.StatusCompleted,getdate()) < 30) then 'Final Mod Processing'
	when lm.LossMitStatusCodeid is null or (lm.LossMitStatusCodeid in ('R','C') and lm.LossMitTemplateId like '%mod%') then ''
	when (lm.LossMitStatusCodeid is not null and lm.LossMitTemplateId not like '%mod%') then ''
	when (mm.StatusFinalDocumentsToBeReceived is not null or mm.StatusFinalDocumentsReceivedInReview is not null) then 'Final Mod Processing'
	when mm.StatusCurrent in ('Approved - send final documents','Final documents to be received', 
	'Final documents received - in review', 'Approved send final docs / File Prep', 
	'Final Docs Received - BK Approval Pending','Final Docs Received - Pending Corrections' 
	,'Final Documents Received - In Review') then 'Final Mod Processing'
	when (mm.Verify4thTrialPaymentReceivedDt is not null or mm.Verify3rdTrialPaymentReceivedDt is not null) then '3rd Trial Payment Received'
	when mm.Verify2ndTrialPaymentReceivedDt is not null then '2nd Trial Payment Received'
	when mm.VerifyFirstTrialPaymentReceivedDt is not null then '1st Trial Payment Received'
	when mm.statusApprovedSendTrialPackage is not null then 'Trial Offered'
	when mm.StatusTrialToBeAccepted is not null then 'Trial Offered'
end as 'ModStage'
,case
	when LM.LossMitDenialReasonCodeid in ('DL','LP','SP','MI') then 'Completed SS/DIL'
	else ''
	end as 'SSDILStatus'
,FM.ScheduledSaleDt
,FM.SaleDt
,LMST.G58_Date
,LMST.R33_Date
,LMST.L49_DATE
,LMST.L50_Date
,LMST.G59_Date
,LMST.G60_Date
,LM.InvestorId
,LM.DelinquentStatusCodeId
,LM.DelinquentPaymentCount
,LM.InterestPaidToDt
,LM.NextPaymentDueDt
,LM.PayoffStopCodeId
,COM.ReasonCode
,BM.BorrowerOneConsumerInfoCodeId
,BM.BorrowerTwoConsumerInfoCodeId
,PS.PropertyState
,LM.NativeAmericanLoanFlag
,DATEDIFF(M,LM.NoteDt,cast(GETDATE() as Date)) as Age
,@MEPeriod as 'MEPeriod'
,@Datekey as 'DateKey'
,@Cutoff_1stOfMonth_Prev2Months as Cutoff_1stOfMonth_Prev2Months
,varf.OriginalLoanToValueRatio
,varf.Loanpurposecodeid
--,CASE
--	WHEN lm.FirstServiceFeeRt >= 0.0025 THEN (floor(200*(LM.CurrentInterestRate - lm.FirstServiceFeeRt/2)))/200 --testing
--	ELSE (floor(200*(LM.CurrentInterestRate - 0.0025)))/200
--END AS [PT at Buyout]

--,CASE
--	WHEN lm.FirstServiceFeeRt >= 0.0025 THEN LM.CurrentInterestRate  - (floor(200*(LM.CurrentInterestRate - lm.FirstServiceFeeRt/2)))/200
--	ELSE LM.CurrentInterestRate - (floor(200*(LM.CurrentInterestRate - 0.0025)))/200
--END AS [Svcg Fee at Buyout]


,CASE
	WHEN lm.FirstServiceFeeRt >= 0.0025 THEN (floor(200*(LM.CurrentInterestRate - lm.FirstServiceFeeRt/2)))/200 --testing
	ELSE (floor(200*(LM.CurrentInterestRate - 0.0025)))/200
END AS [PT at Buyout]

,CASE
	WHEN lm.FirstServiceFeeRt >= 0.0025 THEN LM.CurrentInterestRate  - (floor(200*(LM.CurrentInterestRate - lm.FirstServiceFeeRt/2)))/200
	ELSE LM.CurrentInterestRate - (floor(200*(LM.CurrentInterestRate - 0.0025)))/200
END AS [Svcg Fee at Buyout]


,CASE
	WHEN lm.investorid BETWEEN '400' AND '498' THEN 'GNMA'
	WHEN lm.investorid IN ('025','027') THEN 'Balance Sheet'
	ELSE 'UNKNOWN'
END AS [Source]



From smd..Loan_Master LM
--From (select * from smd..Loan_Master_ME where MEPeriod = 201711) LM

Left join smd..Modification_Master MM
on LM.LoanId = MM.LoanId
--Left join smd..Modification_Master_ME MM 
--on LM.LoanId = MM.LoanId and LM.MEPeriod = MM.MEPeriod

Left join smd..ref_LoanStatus LS
on LM.LoanStatusId = LS.LoanStatusId

Left join 
	(select LoanId,PropertyState 
	from srd..Portfolio_Summary)
PS on LM.LoanId = PS.LoanId

Left join smd..Foreclosure_Master FM 
on LM.LoanId = FM.LoanId
--Left join smd..Foreclosure_Master_ME FM 
--on LM.LoanId = FM.LoanId and LM.MEPeriod = FM.MEPeriod

Left join pennybank.dbo.lossmitigation_step_transpose LMST 
on LM.LoanId = LMST.LoanId



Left join 
	(select LoanId, ReasonCode = '001' 
	from smd..Collection_CommentActivity 
	where ReasonCode = '001' 
	group by LoanId) 
COM on LM.LoanId = COM.LoanId

Left join smd..Borrower_Master BM 
on LM.LoanId = BM.LoanId
--Left join smd..Borrower_Master_ME BM 
--on LM.LoanId = BM.LoanId and LM.MEPeriod = BM.MEPeriod

	LEFT JOIN
	(Select
		lmgb.LoanId,lmgb.LoTypeId,
		lmgb.LoanPurposeCodeId,
		lpgb.LoanPurposeCodeDesc,
		lmgb.OriginalLoantovalueratio
		from smd..Loan_Master lmgb
			Left join smd..ref_LoanPurposeCode lpgb on lmgb.LoanPurposeCodeId = lpgb.LoanPurposeCodeId
		where lmgb.Lotypeid='2' and lmgb.OriginalLoanToValueRatio>'.90' and lmgb.Loanpurposecodeid in ('5','6','7')
		group by lmgb.LoanId, lmgb.LoTypeId, lpgb.LoanPurposeCodeDesc, lmgb.LoanPurposeCodeId, lpgb.LoanPurposeCodeId, lmgb.OriginalLoantovalueratio
		) varf on lm.LoanId = varf.LoanId


Where 

-------------------------------------------------------------- Insert LoanIds here --------------------------------------------------------------------------
--LM.Loanid in ()
((LM.DelinquentStatusCodeId in ('2','3','4','F') and LM.InvestorId between '400' and '498') or (LM.DelinquentStatusCodeId in ('1','2','3','4','F') and LM.InvestorId in ('025','027')) )
--and LM.LoanStatusId in ('2','3','4','F')
--and LM.InvestorId between '400' and '498' or LM.InvestorId in ('025','027')
and LM.CurrentPrincipalBalanceAmt > 0.01
and LM.LoTypeId in (1,2,9)) 


--LM.LoanId in ()
--LM.DelinquentStatusCodeId in ('2','3')
--LM.LoanStatusId in ('2','3','4')
--and LEFT(LM.InvestorId,1) = '4'
--and LM.LoTypeId in (1,2,9)
--and coalesce(LM.TradeId,'') not in ('201308002','201502001','201504001')

--Apply loan level scrubs including Collateral from Contract Finance

select 
LoanId
,TradeCollateral
,LoTypeId
,LoanType
,RunDt
,LoanStatus
,CurrentPrincipalBalanceAmt
,CurrentInterestRate
,SFee
,DebentureRate
,ARMFlag
,LossMitStatusCodeid
,LossMitTemplateId
,LossMitDenialReasonCodeid
,StatusCurrent
,ModStage
,SSDILStatus
,ScheduledSaleDt
,SaleDt
,InvestorId
,DelinquentStatusCodeId
,DelinquentPaymentCount
,InterestPaidToDt
,NextPaymentDueDt
,PayoffStopCodeId
,PropertyState
,Age
,case
	when PayoffStopCodeId <> '0' then 'PIF'
	when NativeAmericanLoanFlag = '1' then 'NAHousing'
	when Lotypeid='2' and OriginalLoanToValueRatio>'.90' and Loanpurposecodeid in ('5','6','7') THEN 'VA_Refi'
	--when Loanid in (select distinct LoanNumber from portfolio_strategy.bumblebee.PLSEBOCollateral201702)  then 'Collateral'
	---commented this out after error --when Loanid in (select distinct loannumber from portfolio_strategy.megatron.Level2ExceptionLoans)  then 'Unsaleable Loan' ---commented this out after error
	when LoanId in (1002013712,1001898972) then 'Franklin American'
	when ARMFlag  = 'Y' then 'ARM'
	when LoanId in (8019110169) then 'Unsaleable Loan'
	when DelinquentStatusCodeId in ('P','A','B','C','D') then '< 30 DAYS DQ'
	when CurrentPrincipalBalanceAmt < '30000' then 'Low Balance'
	when CurrentInterestRate < '0.0275' then 'Low Rate'
	when LossMitStatusCodeId = 'A' and LossMitTemplateId = 'HHF' then 'HHF'
	when (ReasonCode = '001' or BorrowerOneConsumerInfoCodeId = 'X' or BorrowerTwoConsumerInfoCodeId = 'X') then 'Deceased Borrower'
	--when LoanId in (select distinct LoanNumber from portfolio_strategy.bumblebee.DeceasedBorrowers) then 'Deceased Borrower'	
	when ModStage = 'Final Mod Processing' then 'Final Mod Processing'
	when ModStage in ('2nd Trial Payment Received','3rd Trial Payment Received') then ModStage
	when SSDILStatus = 'Completed SS/DIL' then 'Completed SS/DIL'
	when (LossMitTemplateId in ('HAFS', 'SS') and LossMitStatusCodeId = 'A' and (G58_DATE is not null OR R33_Date is not null)) then 'Short Sale Claim Completed'
	when (LossMitTemplateId in ('HAFD', 'DIL2') and LossMitStatusCodeId = 'A' and (L49_DATE is not null OR G59_Date is not null OR L50_Date is not null OR G60_Date is not null)) then 'DIL Claim Completed'	
	when SaleDt is not null then 'FCSale'
	when ScheduledSaleDt>=@Cutoff_1stOfMonth_Prev2Months then 'FCSale'
	else ''	
	end as EligibilityScrub	
,MEPeriod
,DateKey
,Cutoff_1stOfMonth_Prev2Months
,OriginalLoanToValueRatio
,Loanpurposecodeid
,[PT at Buyout]
,[Svcg Fee at Buyout]
,[Source]
,CASE
	WHEN [Svcg Fee at Buyout] > 0.00625 THEN 'Warning - High SFee'
	ELSE ''
END AS [Servicing Fee Check] 


from cte_EBOScrub


