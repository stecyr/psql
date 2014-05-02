

CREATE OR REPLACE FUNCTION patate_search(IN in_phrase text, IN nombre integer)
  RETURNS TABLE(unique_id character varying, result text, ts text, ordre real) AS
$BODY$
/******************************************************************************************
 table  patate

******************************************************************************************/
DECLARE
	strSelect text;
	 
	recRetour record;
BEGIN 
	SELECT btrim(in_phrase) INTO in_phrase;
	DROP TABLE IF EXISTS autoCorrection;
	CREATE TEMPORARY TABLE autoCorrection AS 
		SELECT DISTINCT to_tsquery( 'fr', array_to_string(regexp_split_to_array((suggestion), E'\ +' ),'&')  )  as query ,  suggestion 
		FROM  
		suggest_generique( in_phrase, ' patate',false, 3);
	 
	IF in_phrase = '' THEN strSelect := 'SELECT * FROM  patate_search_index i';
	ELSE strSelect := concat ('SELECT * FROM (
					SELECT pk, champPouraffichage as sugestion,				   
					     ts_headline(''fr'',champ1,query,''MinWords=100,MaxWords=110'') as hl , 				    
					     (  ts_rank_cd(champ1, query) + ts_rank_cd(champ2, query) ) AS ordre
					FROM     patate_search_index i JOIN autoCorrection ON ( champ1 @@ query  ) OR (champ2 @@ query)
					GROUP BY pk, champPouraffichage,hl ,query, ordre 
					) sr 
					ORDER BY ordre DESC LIMIT ', nombre);						
	END IF; 
	
	raise notice 'SELECT  %',strSelect; 

	FOR recRetour IN EXECUTE strSelect
	LOOP
		RETURN QUERY SELECT recRetour.pk, recRetour.sugestion, recRetour.hl ,recRetour.ordre;
	END LOOP;
	
	IF recRetour.unique_id IS NULL THEN RAISE notice 'reponse %',recRetour.unique_id;  
	
 raise notice 'Marche pas avec ET'; 
	--On change l'opérateur ET (&) pour un OU (|)
		UPDATE autoCorrection SET query = to_tsquery( 'fr', array_to_string(regexp_split_to_array((suggestion), E'\ +' ),'|')  ) ;
		FOR recRetour IN EXECUTE strSelect
		LOOP
			RETURN QUERY SELECT recRetour.pk, recRetour.sugestion, recRetour.hl ,recRetour.ordre;
		END LOOP;
	END IF;

 raise notice 'fin'; 
	
END;
$BODY$
  LANGUAGE plpgsql VOLATILE STRICT
  COST 100
  ROWS 1000;
