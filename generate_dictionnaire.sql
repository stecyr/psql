-- Function: generate_dictionnaire(character varying, anyarray, character varying)

-- DROP FUNCTION generate_dictionnaire(character varying, anyarray, character varying);

CREATE OR REPLACE FUNCTION generate_dictionnaire(table_to_index character varying, listechamps anyarray, pk character varying)
  RETURNS character varying AS

/******************************************************************************************

D 	Description:
	Fonction servant a générer les tables nécessaires a l'indexation fts et trigram
	
A	Arguments : 
	table_to_index: nom de la tables a indexé
	listechamps: liste du ou des champs  devant être indexé.
	pk : le nom du champ pk de la tables (obligatoire)
		
S	Postconditions: les tables table_to_index_search_index et table_to_index_dict seront créées

H  	Historique:

    	Stéphane Cyr   Création 
******************************************************************************************/
$BODY$

DECLARE
	tableExists boolean;	 
	liste character varying;
	champs character varying;
	ts_champs character varying;
	i integer;
	rec_champ record;
BEGIN 

/*TODO si pk est null sortir avec message erreur*/

SELECT array_to_string(  array_agg(concat (nom , ' text')) ,',' ) FROM unnest ( listeChamps )   as nom  INTO champs;
SELECT array_to_string(  array_agg(concat ('ts_', nom , ' tsvector')) ,',' ) FROM unnest (listeChamps)  as nom INTO ts_champs;

/*Détermine si la table a indexé existe.*/
EXECUTE concat ('SELECT relname=',quote_literal(concat(table_to_index,'_search_index')), 'FROM pg_class WHERE relname = ',quote_literal(concat(table_to_index,'_search_index')), ' AND relkind IN (''r'',''v'')') INTO tableExists;

IF tableExists='t' THEN 
	EXECUTE  concat( 'DROP TABLE IF EXISTS ',table_to_index, '_search_index');
END IF;

	EXECUTE  concat('CREATE UNLOGGED TABLE ',table_to_index,'_search_index( ', pk,',', champs,',',ts_champs ,')' );

	SELECT array_to_string(listeChamps,',') INTO liste;
 
	EXECUTE concat ('INSERT INTO ',table_to_index,'_search_index  ( ',split_part(pk,' ',1),',',liste,')
			 SELECT ',split_part(pk,' ',1),',',liste,' FROM ' ,table_to_index);

	/*Le setweith est hardCodé a 'A' sinon il faudra ajouter le poids a chacune des colonnes en parametres*/ 	
	FOR rec_champ IN SELECT unnest ( listeChamps ) as c   
	LOOP
		EXECUTE	concat ('UPDATE ',table_to_index,'_search_index SET ts_',rec_champ.c,' =  setweight (to_tsvector(''fr'', ',rec_champ.c,'), ''A'')');

		EXECUTE concat('CREATE INDEX ',table_to_index,'_',rec_champ.c,'_search_index_gin_indx ON ',table_to_index,'_search_index USING gin(ts_',rec_champ.c,')');

	END LOOP; 

	/*Création du dictionnaire*/
	i=0;
	FOR rec_champ IN SELECT unnest ( listeChamps ) as c   
	LOOP		
		IF i=0 THEN

			EXECUTE concat('DROP TABLE IF EXISTS dictionnaire_tmp1; 
				        CREATE TEMPORARY TABLE dictionnaire_tmp1 (ids serial,', split_part(pk,' ',1) ,' ', 
										  substring (pk from strpos(pk,(split_part(pk,' ',2))) for (select  length(pk)) ),
										',mot text )');
  		END IF;
		
		EXECUTE concat('INSERT INTO dictionnaire_tmp1(',split_part(pk,' ',1),', mot) SELECT ',split_part(pk,' ',1), ', lower(btrim (unnest( regexp_split_to_array(strip (to_tsvector( ''simple'', ', rec_champ.c,' ) )::text ,  '' '') ),'''''''') )as mot 
		FROM ',table_to_index,'_search_index');
		
		i=i+1;	

	END LOOP; 

	DROP TABLE IF EXISTS dictionnaire_tmp2;
	CREATE TEMPORARY TABLE dictionnaire_tmp2 AS 
	SELECT  array_agg(DISTINCT(mot))  as mots, array_agg (DISTINCT(ids))  as ids 
		FROM dictionnaire_tmp1 
		GROUP BY mot;
	DROP TABLE IF EXISTS dictionnaire_tmp;
	CREATE TEMPORARY TABLE dictionnaire_tmp AS 
		SELECT unnest (mots) as mot, ids, null::text as diacritique 
		FROM dictionnaire_tmp2;

	UPDATE dictionnaire_tmp set mot = btrim( formatteadresse( mot ) );
 
	UPDATE dictionnaire_tmp set diacritique =  ts_lexize('french_stem',unaccent(mot));
 
	EXECUTE  concat('DROP TABLE IF EXISTS ',table_to_index,'_dict'); 
	EXECUTE concat('CREATE TABLE ',table_to_index,'_dict 
			(
			  mot text,
			  ids integer[],
			  diacritique text
			)');
			
	EXECUTE concat('INSERT INTO ',table_to_index,'_dict (mot,ids,diacritique)
                SELECT b.mot,b.ids,b.diacritique
                FROM dictionnaire_tmp b');

	EXECUTE concat('CREATE INDEX ',table_to_index,'_dict_dia_trgm_indx
	  ON ',table_to_index,'_dict
	  USING gist
	  (diacritique COLLATE pg_catalog."default" gist_trgm_ops)');
	 
	EXECUTE concat('CREATE INDEX  ',table_to_index,'_dict_mot_trgm_indx
	  ON ',table_to_index,'_dict
	  USING gist
	  (mot COLLATE pg_catalog."default" gist_trgm_ops)');

	EXECUTE concat ('GRANT SELECT ON ',table_to_index,'_search_index  TO lecture_geo');
	EXECUTE concat ('GRANT SELECT ON ',table_to_index,'_dict  TO lecture_geo');

   
return 'ok';        

END;

$BODY$
  LANGUAGE plpgsql VOLATILE STRICT
  COST 100;
ALTER FUNCTION generate_dictionnaire(character varying, anyarray, character varying)
  OWNER TO admgeo1;
