(ns sample.core)

(def answer 42)
(defonce cached 1)
(defn square [x] (* x x))
(defn cube [x] (* x x x))
; Shadows a special-form name so a metadata-prefixed `(doto …)` that leaked past the special-form gate
; would resolve here and show as a call (an unresolved `if` never shows, so it alone cannot fail).
(defn doto [x] x)
(defn join [xs] xs)
(defn qualified-join [] (str/join "," ["a" "b"]))
(defn- secret [x] (square x))
(defmacro unless [pred & body] `(if (not ~pred) ~@body))
(defmacro documented "doc" {:added "1"} [x] (list 'square x))
(defmulti area :shape)
(defmethod area :circle [{:keys [radius]}] (square radius))
(defmethod route [:get :admin] [request] request)
(#_(ignored) defn #_(ignored-name) spaced [x] (square x))
(; a comment may separate a list opener from its head
 defn ; or a definition head from its name
 commented [x] (square x))
(defn gap-call [x] (#_(ignored-call) square x))
(defn comment-call [x] (; a comment may precede a call head
                        square x))
(defprotocol Greeter (greet [this]))
(defrecord Person [name] Greeter (greet [_] (str "Hi " name)))
(deftype Counter [value])

(def quoted '(defn phantom [] (missing-call)))
(defn quoted-holder [] '(square 1))
(defn comment-holder [] (comment (square 1)))
`(defn phantom2 [] (other-missing))
#_(defn discarded [] (never-called))

(defn interop []
  (java.lang.String/.toUpperCase "x")
  (Math/abs -1)
  String/1)

(defn run [x] (secret x))

(defn plain-call []
  (square 3))

(defn meta-call []
  ^{:doc "tagged"} (square 4))

(defn tag-call []
  ^String (square 5))

(defn stacked-meta-call []
  ^:a ^{:b 1} (square 6))

(defn quoted-meta []
  '(^{:doc "inert"} (cube 6)))

(defn special-form-metadata []
  ^{:doc "special"} (if true 1 2)
  ^{:doc "special"} (doto 1))

(defn metadata-not-call []
  ^:private square)

(defn nested-quote [] ''(square 1) (secret 1))
(defn nested-discard [] #_(do #_(square 1) (square 2)) (secret 1))
(defn nested-comment [] (comment (comment (square 1)) (square 2)) (secret 1))
(defn comment-not-head [] (do comment (square 1)))
(defn comment-x [x] x)
(defn comment-x-holder [] (comment-x (square 1)))
(def before-discard (square 1))
#_(def discarded-value (square 2))
(def after-discard (square 3))
(defmacro quoted-macro [] '(square 1) (secret 1))
(defn a [] 1)
(defn b [] 2)
(defn syntax-quote-hole [] `(a ~(b)))
(defn live-hole-control [] (b))
