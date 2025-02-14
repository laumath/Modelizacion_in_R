#' ---
#' title: "Selección de Variables Datos Vino"
#' author: "Guillermo Villarino"
#' date: "Otoño 2021"
#' output: rmdformats::readthedown
#' ---
#' 
## ----setup, include=FALSE---------------------------------------------------------------------------------------------
knitr::opts_chunk$set(echo = TRUE, warning = FALSE, message = FALSE)

#' 
#' ## Preliminares
#' 
#' En este documento se presentan varias alternativas para las selección automática de variables en modelos de regresión. Esta técnicas automáticas resulta útiles cuando nos enfrentamos a gran cantidad de variables y esto hace que el proceso manual sea difícil de abordar. En cualquier caso, hemos de saber que no son mágicas y que tienen sus debilidades, por lo que el control de las mismas por nuestra parte se hace fundamental de cara a la obtención de buenos resultados en su aplicación. 
#' 
#' En primer lugar se fija el directorio de trabajo donde tenemos las funciones y los datos.
#' 
## ----directorio y funciones, echo=FALSE-------------------------------------------------------------------------------
# Fijar dierectorio de trabajo donde se encuentran funciones y datosvinoDep
setwd('F:/Documentos/Master Comercio 2021-22/Online_Material Minería de Datos_Otoño2021')

# Cargo las funciones que voy a utilizar después
source("Funciones_R.R")

#' 
#' 
## ----paquetes, include=FALSE, echo=FALSE, message=FALSE, warning=FALSE------------------------------------------------
# Cargo las librerias que me van a hacer falta
paquetes(c('questionr','psych','car','corrplot','caret', 
           'ggplot2', 'lmSupport','pROC', 'glmnet'))


#' 
#' Procedemos a la lectura de los datos depurados y con las transformaciones creadas en el código de regresión lineal. 
#' 
## ----lectura datos----------------------------------------------------------------------------------------------------
# Parto de los datos con las transformaciones creado en el código de regresión lineal
datos<-readRDS("F:/Documentos/Master Comercio 2021-22/Online_Material Minería de Datos_Otoño2021/Dia2_Regresion Lineal/todo_cont_Vino.RDS")

#' 
#' 
#' ## Modelo manual ganador
#' 
#' Rescatamos el modelo ganador en nuestro proceso de ajuste manual de modelos de regresión lineal. 
#' 
#' Debido a que habíamos considerado una tramificaión de Azucar por árboles y no guardamos el factor correspondiente en el input. Lo volvemos a generar. 
#' 
#' **Nota**: Es posible que se produzcan variaciones en pasos como este de tramificación e incluso en los modelos cuando ejecutamos todos los códigos desde el primero de depuración de los datos. La razón es la aleatoriedad en la imputación de los datos (recordamos que utilizábamos la opción aleatorio para no subestimar mucho la varianza). Esto produce que el valor de las imputaciones pueda cambiar con cada ejecución de aquel código, con lo que los registros varían ligeramente haciéndolo así mismo los patrones que puedan generar. Cuando las variaciones son pequeñas, no hay problema. Si en algún momento observáramos grandes diferencias habría que replantear las imputaciones. 
#' 
#' 
## ----tramificacion arboles--------------------------------------------------------------------------------------------
# Arbol para tramificar azucar
tree_azucar<-rpart::rpart(varObjCont~Azucar, data = datos, cp=0.005)
tree_azucar

# puntos de corte en 1.64 y 4.58. Tres grupos. 
table(tree_azucar$where)

# Los grupos están ya ordenados pero se llaman 3 4 y 5

# Añadimos la variable tramificada al dataset
datos$Azucar_tree<-factor(tree_azucar$where)

# Cambiamos los niveles
levels(datos$Azucar_tree) = c('<1.64','1.64-4.58','>4.58')

# Comprobamos
table(datos$Azucar_tree)


#' 
#' Tomamos la partición para implementar nuestro esquema training/test.
#' 
## ----particion--------------------------------------------------------------------------------------------------------
#Hago la partición
set.seed(123456)
trainIndex <- createDataPartition(datos$varObjCont, p=0.8, list=FALSE)
data_train <- datos[trainIndex,]
data_test <- datos[-trainIndex,]

#' 
#' El modelo ganador contenía las variables *Clasificacion*, *Etiqueta*, *CalifProd_cont* y *Azucar_tree*.
#' 
## ----modelo manual lineal---------------------------------------------------------------------------------------------
# Este fue el modelo manual ganador 
modeloManual<-lm(varObjCont~Clasificacion+Etiqueta+CalifProd_cont+Azucar_tree,data=data_train)
summary(modeloManual)
Rsq(modeloManual,"varObjCont",data_train)
Rsq(modeloManual,"varObjCont",data_test)

#' 
#' El objetivo es, por tanto, valorar si la selección de variables automática en alguna de sus variantes puede ayudar a mejorar la capacidad predictiva del modelo sin aumentar muchísimo la complejidad.
#' 
#' Abordamos la selección de variables "clasica" mediante la función *step()* de R. El objetivo de esta función es proponer un subconjunto de variables que considera óptimo en relación a una determinada métrica (Criterio de Akaike o Criterio de Información Bayesiana/Criterio de Schwarz) de entre todas las disponibles. 
#' 
#' Nuestro plan es variar tanto la métrica como las variables o efectos disponibles. De esta forma haremos pruebas con los distintos criterios para conjuntos de variables con complejidad creciente.
#' 
#' 1) Variables originales
#' 2) Variables originales + interacciones
#' 3) Variables originales + transformaciones
#' 4) Variables originales + interacciones + transformaciones
#' 
#' 
#' ## Selección de variables clásica con variables originales
#' 
#' La función *step()* tiene 3 formas de proceder: 
#' 
#' 1) Hacia delante (forward): Partiendo del modelo nulo (solo con la constante), introduce uno a uno los efectos desde el más importante en cuanto a su aportación al R2 (verosimilitud en caso de regresión logística). Cuando un efecto entra, ya no puede salir. 
#' 
#' 2) Hacia atrás (backward): Partiendo del modelo completo (todas las variables), elimina uno a uno los efectos desde el menos importante en cuanto a su aportación al R2 (verosimilitud en caso de regresión logística). Cuando un efecto sale, ya no puede entrar. 
#' 
#' 3) Por pasos (Stepwise/ both en step()): Realiza el forward pero valorando el efecto de la salida de variables que ya fueron incluidas en modelo. Las variables pueden entrar y volver a salir del modelo (pueden darse efectos de confusión entre variables) 
#' 
#' Para implementar esta técnica necesitamos:
#' 
#' - un modelo null 
#' - un modelo full (aquí es donde se controlan el número de efectos disponibles)
#' - dirección de proceso de entre las 3 anteriores
#' - métrica para la función objetivo del algoritmo: AIC (menor penalización de número d parámetros --> tendencia a modelo más complejos) ó BIC/SBC (mayor penalización de número d parámetros --> tendencia a modelos más simples)
#' 
#' Vamos a probar con ambas métricas y dirección step y backward --> 4 modelos.
#' 
#' 
## ----seleccion variables clasica variables originales-----------------------------------------------------------------
# Seleccion de variables "clásica"
null<-lm(varObjCont~1, data=data_train) #Modelo minimo
full<-lm(varObjCont~.-ID, data=data_train[,c(1:18,33,34)]) #Modelo maximo, le quitamos las transformaciones

modeloStepAIC<-step(null, scope=list(lower=null, upper=full), direction="both", trace = F)
summary(modeloStepAIC)
Rsq(modeloStepAIC,"varObjCont",data_test)

modeloBackAIC<-step(full, scope=list(lower=null, upper=full), direction="backward", trace = F)
summary(modeloBackAIC)
Rsq(modeloBackAIC,"varObjCont",data_test) #son iguales

modeloStepBIC<-step(null, scope=list(lower=null, upper=full), direction="both",k=log(nrow(data_train)), trace = F)
summary(modeloStepBIC)
Rsq(modeloStepBIC,"varObjCont",data_test) 

modeloBackBIC<-step(full, scope=list(lower=null, upper=full), direction="backward",k=log(nrow(data_train)), trace = F)
summary(modeloBackBIC)
Rsq(modeloBackBIC,"varObjCont",data_test) # son iguales

modeloStepAIC$rank
modeloStepBIC$rank



#' 
#' ## Selección de variables clásica con variables originales y sus interacciones
#' 
#' Ahora vamos a dejar que la función *step()* pueda seleccionar interacciones entre las variables originales. Para ello, disponemos de una función llamada *formulainteracciones()* que genera la cadena de caracteres al estilo fórmula con todas las interacciones de variables categóricas y continuas con categóricas. Este será el modelo full para el proceso.
#' 
#' 
## ----seleccion variables clasica interacciones------------------------------------------------------------------------
#Genero interacciones
formInt<-formulaInteracciones(datos[,c(1:18,33,34)],19)#en el subconjunto de las vbles. originales, la objetivo está en la columna 17
fullInt<-lm(formInt, data=data_train)

modeloStepAIC_int<-step(null, scope=list(lower=null, upper=fullInt), direction="both", trace = F)
summary(modeloStepAIC_int)
Rsq(modeloStepAIC_int,"varObjCont",data_test) #Parecen algo mejores que los anteriores training pero generalizan peor

modeloStepBIC_int<-step(null, scope=list(lower=null, upper=fullInt), direction="both",k=log(nrow(data_train)), trace = F)
summary(modeloStepBIC_int)
Rsq(modeloStepBIC_int,"varObjCont",data_test) #Un pelin mejor

modeloStepAIC_int$rank #muchos más parámetros
modeloStepBIC_int$rank

#Por el principio de parsimonia, es preferible el modeloStepBIC_int

#' 
#' ## Selección de variables clásica con variables originales y transformaciones
#' 
#' En este caso vamos a probar con las variables originales y sus transformaciones como efectos disponibles. Especial atención aquí a las variables y sus transformaciones juntas en el modelo. En ocasiones, si la aportación al modelo es significativa se pueden mantener ambas, pero esto puede generar gran problema de colinealidad en el modelo y dificultad asegurada en la interpretación de los parámetros.
#' 
#' Lo ideal sería revisar el modelo posteriormente e intentar eliminar alguna de ellas valorando la pérdida de R2.
#' 
#' 
## ----seleccion variables clasica transformaciones---------------------------------------------------------------------
# Pruebo con todas las transf 
fullT<-lm(varObjCont~., data=data_train)

modeloStepAIC_trans<-step(null, scope=list(lower=null, upper=fullT), direction="both", trace = F)
summary(modeloStepAIC_trans)
Rsq(modeloStepAIC_trans,"varObjCont",data_test)

modeloStepBIC_trans<-step(null, scope=list(lower=null, upper=fullT), direction="both",k=log(nrow(data_train)), trace = F)
summary(modeloStepBIC_trans)
Rsq(modeloStepBIC_trans,"varObjCont",data_test) 

modeloStepAIC_trans$rank 
modeloStepBIC_trans$rank



#' 
#' ## Selección de variables clásica con variables originales y transformaciones y sus interacciones
#' 
#' Aplicamos ahora la función de interacciones con todas las transformaciones obteniendo el set más completo de efectos.
#' 
## ----seleccion variables clasica transformaciones e interacciones-----------------------------------------------------
#Trans e interacciones
formIntT<-formulaInteracciones(datos,33)
fullIntT<-lm(formIntT, data=data_train)

modeloStepAIC_transInt<-step(null, scope=list(lower=null, upper=fullIntT), direction="both", trace = F)
summary(modeloStepAIC_transInt)
Rsq(modeloStepAIC_transInt,"varObjCont",data_test) # se parece el valor a los int sin transf

modeloStepBIC_transInt<-step(null, scope=list(lower=null, upper=fullIntT), direction="both",k=log(nrow(data_train)), trace = F)
summary(modeloStepBIC_transInt)
Rsq(modeloStepBIC_transInt,"varObjCont",data_test) # 

modeloStepAIC_transInt$rank 
modeloStepBIC_transInt$rank

#Por el principio de parsimonia, es preferible el modeloStepBIC_transInt

#' 
#' Los modelos tienen bastante efectos y la interacción de clasificación y etiqueta vuelve a aparecer. Claramente mejor el BIC que el AIC.
#' 
#' 
#' ## Evaluación por validación cruzada repetida de los modelos se selección clásica
#' 
## ----evaluacion por validacion cruzada--------------------------------------------------------------------------------
## Pruebo los mejores de cada con validacion cruzada repetida
total<-c()
modelos<-sapply(list(modeloManual,modeloStepAIC,modeloStepBIC,modeloStepBIC_int,
                     modeloStepAIC_trans,modeloStepBIC_trans,modeloStepBIC_transInt),formula)
for (i in 1:length(modelos)){
  set.seed(1712)
  vcr<-train(as.formula(modelos[[i]]), data = data_train,
             method = "lm",
             trControl = trainControl(method="repeatedcv", number=5, repeats=20,
                                      returnResamp="all")
  )
  total<-rbind(total,cbind(vcr$resample[,1:2],modelo=rep(paste("Modelo",i),
                                                         nrow(vcr$resample))))
}
boxplot(Rsquared~modelo,data=total,main="R-Square") 
aggregate(Rsquared~modelo, data = total, mean) #el 4 y el 7 son mejores
aggregate(Rsquared~modelo, data = total, sd) 

#' 
#' 
## ----metricas validacion cruzada--------------------------------------------------------------------------------------
#vemos el número de parametros
length(coef(modeloStepBIC_int))
length(coef(modeloStepBIC_transInt))

# El primero tiene dos interacciones, el segundo una tranformación y azucar_tree

formula(modeloStepBIC_int)
formula(modeloStepBIC_transInt)



#' 
#' ## Esquema de selección aleatoria de variables
#' 
#' La idea que hay detrás de la selección aleatoria de variables, es la de someter a la función *step()* a muchas pruebas de robustez. Para ello, no es descabellado pensar que si le pedimos a step que trabaje con submuestras de los datos que contienen distintas observaciones cada vez, la selección de variables no estará condicionada por el conjunto de entrenamiento o no sobreajustará al mismo. 
#' 
#' Lo que hacemos es repetir (de nuevo empirismo) el proceso clásico varias veces con distintos registros y evaluamos la estabilidad de los resultados. Parece lógico que si una selección de variables se mantiene inalterada en distintos conjuntos de observaciones, ese set de variables es robusto en capacidad de generalización.
#' 
#' 
#' Es tan simple como generar un bucle que repita el proceso *step()* con submuestras de datos, una vez generados se crea un dataframe de fórmulas y se cuenta cuantas veces aparece cada una. Se presenta una tabla de frecuencias para la valoración final. 
#' 
#' La guardaremos en el objeto fr para poder acceder a las fórmulas más frecuentes posteriormente.
#' 
## ----selección aleatoria----------------------------------------------------------------------------------------------
## Seleccion aleatoria

rep<-20
prop<-0.7
modelosGenerados<-c()
for (i in 1:rep){
  set.seed(12345+i)
  subsample<-data_train[sample(1:nrow(data_train),prop*nrow(data_train),replace = T),]
  full<-lm(formIntT,data=subsample)
  null<-lm(varObjCont~1,data=subsample)
  modeloAux<-step(null,scope=list(lower=null,upper=full),direction="both",trace=0,k=log(nrow(subsample)))
  modelosGenerados<-c(modelosGenerados,paste(sort(unlist(strsplit(as.character(formula(modeloAux))[3]," [+] "))),collapse = "+"))
}
(freq(modelosGenerados,sort="dec")->fr)

# Guardo la tabla de frecuancias para luego seleccionar los más relevantes y probarlos

#' 
#' Podemos seleccionar los 3 mejores modelos por ejemplo y enfrentarlos en la comparación final.
#' 
#' # Esquema de selección de variables por Lasso
#' 
#' Lasso es en realidad un método de regresión en sí mismo, cuya particularidad reside en que la optimización por mínimos cuadrados/máxima verosimilitud se ve restringida por una condición que no existía en regresiones ordinarias. Esta condición aplica al sumatorio del valor de los parámetros del modelo, esta restricción hace que el método pueda ser considerado como un selector de variables directamente. 
#' 
#' No es el objetivo entrar en el proceso matemático subyacente a esta técnica y nos conformaremos con aplicarla como posible método de selección de variables. Si conviene saber que Lasso maneja un parámetro lambda que es encargado de cuantificar el peso que la restricción sobre los parámetros debe tener para una solución con error de estimación controlado. De esta forma, el primer paso es buscar ese valor de lambda (usualmente el que se encuentra a 1 desviación típica de mínimo para penalizar lo suficiente pero no tanto como para que el error se dispare) y con el evaluar el modelo por validación cruzada. 
#' 
#' La función *cv.glmnet()* permite hacer esta operación, si bien requiere del uso previo de la función *model.matrix()* que realiza una extensión de las variables nominales a *dummies* y deja el archivo como lo necesita este paquete. 
#' 
#' 
## ----Lasso------------------------------------------------------------------------------------------------------------
## LASSO, lo hacemos sin interacciones pues, de lo contrario, puede coger interacciones y no las variables que las forman
y <- as.double(as.matrix(data_train[, 33]))
x<-model.matrix(varObjCont~., data=data_train)[,-1]#no cambiar el -1
set.seed(1712)
cv.lasso <- cv.glmnet(x,y,nfolds=5)
plot(cv.lasso)

#' 
#' Este es el comportamiento de lambda y el intervalo de 1se. Mostramos lo coeficiente.
#' 
## ---------------------------------------------------------------------------------------------------------------------
(betas<-coef(cv.lasso, s=cv.lasso$lambda.1se))

#' 
#' Todos aquellos que aparecen con un . han sido descartados del modelo n base al cumplimiento de la restricción para ese valor de lambda que se suele considerar óptimo. 
#' 
#' Podemos observar que ha considerado calificación del productor 2 veces, como original y su transformada identidad (previo escalado y suma del mínimo). Esto como podemos intuir puede dar lugar a problemas de colinealidad. 
#' 
#' Por otra parte, al extenderse las nominales en dummies es posible que aparezcan efectos d niveles independientemente de la consideración de otros de la misma variable. Este es el caso de calificación de productor nominal en su categoría 5-12.
#' 
#' ## Comparativa final y selección del modelo ganador
#' 
#' Finalmente vamos a considerar los modelos que parecen mejores en selección automática de variables "clásica", aleatoria y lasso junto con el modelo manual de referencia y sencillo.
#' 
## ----Comparacion final por validacion cruzada-------------------------------------------------------------------------
## Comparación final, tomo el ganador de antes y los nuevos candidatos
total2<-c()
modelos2<-c(formula(modeloManual),formula(modeloStepBIC_transInt),
            as.formula(paste('varObjCont ~', rownames(fr)[1])),
            as.formula(paste('varObjCont ~', rownames(fr)[2])),
            as.formula(paste('varObjCont ~', rownames(fr)[3])))
for (i in 1:length(modelos2)){
  set.seed(1712)
  vcr<-train(as.formula(modelos2[[i]]), data = data_train,
             method = "lm",
             trControl = trainControl(method="repeatedcv", number=5, repeats=20,
                                      returnResamp="all")
  )
  total2<-rbind(total2,cbind(vcr$resample[,1:2],modelo=rep(paste("Modelo",i),
                                                         nrow(vcr$resample))))
}
set.seed(1712)
lassovcr <- train(varObjCont ~ ., data = data_train, 
                  method = "glmnet",
                  tuneGrid=expand.grid(.alpha=1,.lambda=cv.lasso$lambda.1se),
                  trControl = trainControl(method="repeatedcv", number=5, repeats=20,
                                           returnResamp="all")
)
total2<-rbind(total2,cbind(lassovcr$resample[,1:2],modelo=rep("LASSO",
                                                         nrow(vcr$resample))))

boxplot(Rsquared~modelo,data=total2,main="R-Square") #el lasso funciona peor
aggregate(Rsquared~modelo, data = total2, mean) 
aggregate(Rsquared~modelo, data = total2, sd) 

#Una vez decidido el mejor modelo, hay que evaluarlo (ver final del CódigoRegLineal)

#Este código se puede aplicar a regresión logística con pequeñas modificaciones (básicamente cambiar lm() por glm(), 
#con la opción family=binomial) Para ello, ver código del pdf RegresiónLogísticaconR


#' 
#' En este punto tenemos un modelo manual generado en la práctica 2 que resultaba sencillo y no muy lejano en capacidad predictiva con respecto a otros mas complejos. En esta parte de selección de variables, todos los métodos excepto Lasso abogan por mantener la interacción de las variables clasificación y etiqueta con un ligera mejora de la capacidad predictiva pero, a su vez, un importante aumento en el número de parámetros. 
#' 
#' En validación cruzada estamos en niveles de R2 iguales que los de los modelos complejos propuestos en la selección manual con lo que, en términos de mejora de la capacidad predictiva, los métodos de selección de variables no ha supuesto en este caso concreto una mejora sustancial. 
#' 
#' Nos encontramos ante el mismo dilema que en la práctica 2. Decidirnos por el modelo manual sencillo o ganar 3 centésimas de R eligiendo el modelo con la interacción Clasificación:Etiqueta... En caso de escoger la segunda de las opciones, sería conveniente revisar el modelo y realizar la unión de categorías de clasificación (o probar con etiqueta..) de modo que no aparezcan efectos con NA en las estimaciones con una pérdida de pocas milésimas en términos de R2. 
#' 
#' 
#' 
#' 
