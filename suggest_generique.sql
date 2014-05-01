-- Function: suggest_generique(text, character varying, boolean, integer)

-- DROP FUNCTION suggest_generique(text, character varying, boolean, integer);

CREATE OR REPLACE FUNCTION suggest_generique(IN in_phrase text, IN tablename character varying, IN samedocument boolean, IN nbsuggest integer)
  RETURNS TABLE(suggestion text, affichage text) AS
$BODY$

/******************************************************************************************

D 	Description:
	Orchestateur de correction de le phrase passé en argument.

A	Arguments : 
		in_phrase text, nbsuggest i

S	Sortie : Nil

H  	Historique:

    	Stéphane Cyr            22 Janvier 10             Création.
******************************************************************************************/
DECLARE
	recMots record; 
	strOrder text;
	strGroup  text;
 	strSql text;
 	strSql_full text;
	strSelect text;
	strSelect_full text;
	intCnt integer;
	recRetour record;
	i int;
	j int;
	strValide character varying;
	arrCorrection character varying [][];
	liste integer[];
	tmpliste integer[];
BEGIN
	SELECT count(word) FROM ts_stat('SELECT to_tsvector(''fr'',  '''||in_phrase||''')') into intCnt;
 
	IF  intCnt = 1 THEN 

		FOR recMots IN SELECT outmot FROM correctionmot_generique(in_phrase, tableName ,ARRAY[-1],nbSuggest ) 
		LOOP 		
			RETURN QUERY SELECT recMots.outmot::text,
					    ts_headline('fr',recMots.outmot, to_tsquery( 'fr', array_to_string(regexp_split_to_array((in_phrase),E'\ +' ),'|')  ),'MinWords=100,MaxWords=110');
		 
		END LOOP;	
		RETURN;
	ELSE  --Pour une phrase    

		i:=0;

		SELECT  EXTRACT(MICROSECONDS FROM (select CURRENT_TIMESTAMP) ) +  round (random()*10000) INTO j; 

		--Pour chaque mots...
		FOR recMots IN  SELECT distinct unnest( regexp_split_to_array( btrim (in_phrase),E'\ +'))  as word
		LOOP
			IF i=0 THEN liste=ARRAY[-1]; END IF;
						
			IF sameDocument THEN 
				EXECUTE concat ('CREATE TEMPORARY TABLE tempotable',j,' AS SELECT  *, 1 as j 
				FROM correctionmot_generique( ',quote_literal(recMots.word),',',quote_literal(tableName),', ARRAY[',array_to_string(liste,','),'],',nbSuggest,')');
			ELSE 
				EXECUTE concat ('CREATE TEMPORARY TABLE tempotable',j,' AS SELECT  *, 1 as j 
				FROM correctionmot_generique( ',quote_literal(recMots.word),',',quote_literal(tableName),', ARRAY[-1],',nbSuggest,')');
			END IF;
			EXECUTE 'SELECT outmot FROM tempotable'||j||' WHERE outids IS NOT NULL' INTO strvalide;
raise notice 'mot origine %',recMots.word;
raise notice 'mot corrigé %', strvalide;		
			IF strvalide IS NOT NULL THEN 		
				IF i=0 THEN  
					strSelect := 'SELECT concat( tempotable'||j||'.outmot';
					--strSql:=' FROM tempotable'||j;
					strSql_full:=' FROM tempotable'||j;
					strGroup:= ' GROUP BY tempotable'||j||'.tri,tempotable'||j||'.outmot';
					strOrder := ' ORDER BY tempotable'||j||'.tri';
				ELSE 			
						strSelect := strSelect ||','' '' || tempotable'||j||'.outmot';
						--strSql :=strSql||'  JOIN tempotable'||j|| ' ON tempotable'||j||'.outids && tempotable'||j-1||'.outids';				
						strSql_full :=strSql_full||' JOIN tempotable'||j|| ' ON tempotable'||j||'.j = tempotable'||j-1||'.j';
						strOrder := strOrder || ',tempotable'||j||'.tri';
						strGroup := strGroup || ',tempotable'||j||'.tri,tempotable'||j||'.outmot';
				END IF;

				EXECUTE 'SELECT outids FROM tempotable'||j INTO tmpliste;

				IF i=0 THEN liste = tmpliste; 
				ELSE liste = liste || tmpliste; 
				END IF;
	
				i:=i+1;
				j:=j+1;

raise notice 'fin boucle %',i;	

			ELSE EXECUTE 'DROP TABLE tempotable'||j;
				strSelect := strSelect ||',' ||quote_literal(' '||recMots.word);
			END IF;
		END LOOP;
	
	
			strSelect:=strSelect||') as champ ';
			strSelect_full:=strSelect;
			strSelect := strSelect|| ' ' ||strSql ;--|| strOrder;
			strSelect_full := strSelect_full || ' ' ||strSql_full|| ' '  || strGroup|| ' '  ||strOrder;

raise notice 'SQL :%',strSelect_full;

		FOR recRetour IN EXECUTE strSelect_full 
		LOOP
			 RETURN QUERY SELECT recRetour.champ , ts_headline('fr',recRetour.champ, to_tsquery( 'fr', array_to_string(regexp_split_to_array((in_phrase),E'\ +' ),'|')  ),'MinWords=100,MaxWords=110') ;
		END LOOP;			
		
	END IF;

RETURN;	

END;

$BODY$
  LANGUAGE plpgsql VOLATILE STRICT
  COST 100
  ROWS 1000;
ALTER FUNCTION suggest_generique(text, character varying, boolean, integer)
  OWNER TO cyrs03;
